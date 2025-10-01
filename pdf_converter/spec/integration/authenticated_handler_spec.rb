# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'jwt'
require 'webmock/rspec'
require 'fileutils'
require 'base64'
require_relative '../../app'

RSpec.describe 'Authenticated Lambda Handler' do
  let(:valid_secret) { 'test-secret-key-for-jwt-validation' }
  let(:valid_payload) { { user_id: '123', exp: Time.now.to_i + 3600 } }
  let(:valid_token) { JWT.encode(valid_payload, valid_secret, 'HS256') }
  let(:expired_payload) { { user_id: '123', exp: Time.now.to_i - 3600 } }
  let(:expired_token) { JWT.encode(expired_payload, valid_secret, 'HS256') }

  let(:valid_request_body) do
    {
      'source' => 'https://s3.amazonaws.com/bucket/input.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=credential',
      'destination' => 'https://s3.amazonaws.com/bucket/output/?X-Amz-Algorithm=AWS4-HMAC-SHA256',
      'webhook' => 'https://example.com/webhook',
      'unique_id' => 'test-123'
    }
  end

  let(:context) { {} }

  before do
    WebMock.disable_net_connect!

    # Mock AWS Secrets Manager
    secrets_client = instance_double(Aws::SecretsManager::Client)
    allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
    allow(secrets_client).to receive(:get_secret_value)
      .with(secret_id: ENV['JWT_SECRET_NAME'] || 'pdf-converter/jwt-secret')
      .and_return(double(secret_string: valid_secret))

    # Set environment variable for testing
    ENV['JWT_SECRET_NAME'] = 'pdf-converter/jwt-secret'

    # Mock PDF download
    pdf_content = "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n>>\nendobj\nxref\n0 1\n0000000000 65535 f \ntrailer\n<<\n/Size 1\n/Root 1 0 R\n>>\nstartxref\n9\n%%EOF"
    stub_request(:get, /s3\.amazonaws\.com/)
      .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })

    # Mock PDF converter
    mock_converter = instance_double(PdfConverter)
    allow(PdfConverter).to receive(:new).and_return(mock_converter)
    allow(mock_converter).to receive(:convert_to_images).and_return({
                                                                      success: true,
                                                                      images: ['/tmp/test-123/test-123_page_1.png'],
                                                                      metadata: { page_count: 1, dpi: 300,
                                                                                  compression: 6 }
                                                                    })

    # Mock image uploader
    mock_uploader = instance_double(ImageUploader)
    allow(ImageUploader).to receive(:new).and_return(mock_uploader)
    allow(mock_uploader).to receive(:upload_batch).and_return([{
                                                                success: true,
                                                                etag: '"abc123"',
                                                                index: 0
                                                              }])

    # Mock S3 upload requests
    stub_request(:put, /s3\.amazonaws\.com.*page-1\.png/)
      .to_return(status: 200, body: '', headers: { 'ETag' => '"abc123"' })

    # Mock webhook calls
    stub_request(:post, 'https://example.com/webhook')
      .to_return(status: 200, body: '', headers: {})

    # Ensure test image file exists
    FileUtils.mkdir_p('/tmp/test-123')
    File.write('/tmp/test-123/test-123_page_1.png',
               Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='))
  end

  after do
    WebMock.reset!
  end

  describe 'authenticated requests' do
    context 'with valid JWT token' do
      let(:event) do
        {
          'httpMethod' => 'POST',
          'path' => '/convert',
          'headers' => {
            'Authorization' => "Bearer #{valid_token}",
            'Content-Type' => 'application/json'
          },
          'body' => valid_request_body.to_json
        }
      end

      it 'processes request successfully' do
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(200)
        body = JSON.parse(response[:body])
        expect(body['message']).to eq('PDF conversion and upload completed')
        expect(body['unique_id']).to eq('test-123')
        expect(body['status']).to eq('completed')
      end

      it 'includes CORS headers in successful response' do
        response = lambda_handler(event: event, context: context)

        expect(response[:headers]).to include(
          'Content-Type' => 'application/json',
          'Access-Control-Allow-Origin' => '*'
        )
      end
    end

    context 'with missing Authorization header' do
      let(:event) do
        {
          'httpMethod' => 'POST',
          'path' => '/convert',
          'headers' => {
            'Content-Type' => 'application/json'
          },
          'body' => valid_request_body.to_json
        }
      end

      it 'returns 401 Unauthorized' do
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(401)
        body = JSON.parse(response[:body])
        expect(body['error']).to include('Missing Authorization header')
      end

      it 'includes CORS headers in error response' do
        response = lambda_handler(event: event, context: context)

        expect(response[:headers]).to include(
          'Content-Type' => 'application/json',
          'Access-Control-Allow-Origin' => '*'
        )
      end
    end

    context 'with malformed Bearer token' do
      let(:event) do
        {
          'httpMethod' => 'POST',
          'path' => '/convert',
          'headers' => {
            'Authorization' => 'InvalidBearer token123',
            'Content-Type' => 'application/json'
          },
          'body' => valid_request_body.to_json
        }
      end

      it 'returns 401 Unauthorized' do
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(401)
        body = JSON.parse(response[:body])
        expect(body['error']).to include('Invalid Bearer token format')
      end
    end

    context 'with invalid JWT signature' do
      let(:wrong_secret) { 'wrong-secret-key' }
      let(:invalid_token) { JWT.encode(valid_payload, wrong_secret, 'HS256') }
      let(:event) do
        {
          'httpMethod' => 'POST',
          'path' => '/convert',
          'headers' => {
            'Authorization' => "Bearer #{invalid_token}",
            'Content-Type' => 'application/json'
          },
          'body' => valid_request_body.to_json
        }
      end

      it 'returns 401 Unauthorized' do
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(401)
        body = JSON.parse(response[:body])
        expect(body['error']).to include('Invalid signature')
      end
    end

    context 'with expired JWT token' do
      let(:event) do
        {
          'httpMethod' => 'POST',
          'path' => '/convert',
          'headers' => {
            'Authorization' => "Bearer #{expired_token}",
            'Content-Type' => 'application/json'
          },
          'body' => valid_request_body.to_json
        }
      end

      it 'returns 401 Unauthorized' do
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(401)
        body = JSON.parse(response[:body])
        expect(body['error']).to include('Token has expired')
      end
    end

    context 'with malformed JWT token' do
      let(:event) do
        {
          'httpMethod' => 'POST',
          'path' => '/convert',
          'headers' => {
            'Authorization' => 'Bearer not.a.valid.jwt',
            'Content-Type' => 'application/json'
          },
          'body' => valid_request_body.to_json
        }
      end

      it 'returns 401 Unauthorized' do
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(401)
        body = JSON.parse(response[:body])
        expect(body['error']).to include('Malformed token')
      end
    end
  end

  describe 'AWS Secrets Manager errors' do
    context 'when secret cannot be retrieved' do
      before do
        secrets_client = instance_double(Aws::SecretsManager::Client)
        allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
        allow(secrets_client).to receive(:get_secret_value)
          .and_raise(Aws::SecretsManager::Errors::ResourceNotFoundException.new(nil, nil))
      end

      let(:event) do
        {
          'httpMethod' => 'POST',
          'path' => '/convert',
          'headers' => {
            'Authorization' => "Bearer #{valid_token}",
            'Content-Type' => 'application/json'
          },
          'body' => valid_request_body.to_json
        }
      end

      it 'returns 500 Internal Server Error' do
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(500)
        body = JSON.parse(response[:body])
        expect(body['error']).to include('Authentication service unavailable')
      end
    end
  end

  describe 'existing functionality preservation' do
    context 'with valid authentication and request' do
      let(:event) do
        {
          'httpMethod' => 'POST',
          'path' => '/convert',
          'headers' => {
            'Authorization' => "Bearer #{valid_token}",
            'Content-Type' => 'application/json'
          },
          'body' => valid_request_body.to_json
        }
      end

      it 'preserves PDF conversion request structure' do
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(200)
        body = JSON.parse(response[:body])
        expect(body).to include(
          'message' => 'PDF conversion and upload completed',
          'unique_id' => 'test-123',
          'status' => 'completed'
        )
      end

      it 'validates request body requirements' do
        event['body'] = { 'source' => 'https://example.com/pdf' }.to_json
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to include('Missing required field')
      end

      it 'rejects path traversal attempts in unique_id' do
        invalid_request = valid_request_body.dup
        invalid_request['unique_id'] = '../../../etc/passwd'
        event['body'] = invalid_request.to_json

        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to include('Invalid unique_id format')
      end

      it 'rejects unique_id with special characters' do
        invalid_request = valid_request_body.dup
        invalid_request['unique_id'] = 'test/123@#$'
        event['body'] = invalid_request.to_json

        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to include('Invalid unique_id format')
      end

      it 'accepts valid unique_id with allowed characters' do
        valid_request = valid_request_body.dup
        valid_request['unique_id'] = 'valid-test_123'
        event['body'] = valid_request.to_json

        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(200)
      end
    end
  end

  describe 'logging and monitoring' do
    let(:event) do
      {
        'httpMethod' => 'POST',
        'path' => '/convert',
        'headers' => {
          'Authorization' => "Bearer #{valid_token}",
          'Content-Type' => 'application/json'
        },
        'body' => valid_request_body.to_json
      }
    end

    it 'logs authentication success' do
      expect { lambda_handler(event: event, context: context) }
        .to output(/Authentication successful/).to_stdout_from_any_process
    end

    it 'logs authentication failure' do
      event['headers']['Authorization'] = 'Bearer invalid.jwt.token'
      expect { lambda_handler(event: event, context: context) }
        .to output(/Authentication failed/).to_stdout_from_any_process
    end
  end
end

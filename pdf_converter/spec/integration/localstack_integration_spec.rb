# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../app'
require 'aws-sdk-s3'
require 'aws-sdk-secretsmanager'

# Allow connections to LocalStack if WebMock is loaded
begin
  require 'webmock'
  # Allow all connections for LocalStack integration tests
  WebMock.allow_net_connect!
rescue LoadError
  # WebMock not loaded, no action needed
end

RSpec.describe 'LocalStack Integration' do
  let(:localstack_endpoint) { ENV['LOCALSTACK_ENDPOINT'] || 'http://localhost:4566' }
  let(:bucket_name) { 'pdf-converter-test' }
  let(:jwt_secret) { 'test-secret-key-for-localstack-testing-12345' }
  let(:secret_name) { 'pdf-converter/jwt-secret' }

  # Re-enable network connections for LocalStack integration tests
  before do
    WebMock.allow_net_connect! if defined?(WebMock)
  end

  let(:s3_client) do
    Aws::S3::Client.new(
      endpoint: localstack_endpoint,
      region: 'us-east-1',
      credentials: Aws::Credentials.new('test', 'test'),
      force_path_style: true
    )
  end

  let(:s3_presigner) do
    Aws::S3::Presigner.new(client: s3_client)
  end

  let(:secrets_client) do
    Aws::SecretsManager::Client.new(
      endpoint: localstack_endpoint,
      region: 'us-east-1',
      credentials: Aws::Credentials.new('test', 'test')
    )
  end

  before(:all) do
    # Set environment variables for LocalStack
    ENV['AWS_ENDPOINT_URL'] = ENV['LOCALSTACK_ENDPOINT'] || 'http://localhost:4566'
    ENV['AWS_REGION'] = 'us-east-1'
    ENV['JWT_SECRET_NAME'] = 'pdf-converter/jwt-secret'
    ENV['AWS_ACCESS_KEY_ID'] = 'test'
    ENV['AWS_SECRET_ACCESS_KEY'] = 'test'
  end

  describe 'PDF Conversion End-to-End' do
    it 'converts PDF using LocalStack S3 and Secrets Manager' do
      # Generate JWT token
      jwt_token = JWT.encode(
        {
          sub: 'test-client',
          iat: Time.now.to_i,
          exp: Time.now.to_i + 3600,
          service: 'pdf-converter'
        },
        jwt_secret,
        'HS256'
      )

      # Get presigned URLs
      source_url = s3_presigner.presigned_url(
        :get_object,
        bucket: bucket_name,
        key: 'input/test.pdf',
        expires_in: 3600
      )

      dest_url = s3_presigner.presigned_url(
        :put_object,
        bucket: bucket_name,
        key: 'output/page-1.png',
        expires_in: 3600
      )

      # Extract base path for destination
      URI.parse(dest_url)
      # Reconstruct with query params from one of the presigned URLs
      dest_base_with_params = dest_url.sub('/page-1.png', '/')

      # Create Lambda event
      event = {
        'body' => {
          'source' => source_url,
          'destination' => dest_base_with_params,
          'webhook' => 'http://localhost:3000/webhook',
          'unique_id' => 'test-localstack-123'
        }.to_json,
        'headers' => {
          'Authorization' => "Bearer #{jwt_token}",
          'Content-Type' => 'application/json'
        },
        'httpMethod' => 'POST',
        'path' => '/convert'
      }

      # Invoke the Lambda handler
      response = lambda_handler(event: event, context: {})

      # Verify response
      expect(response[:statusCode]).to eq(200)
      body = JSON.parse(response[:body])
      expect(body['status']).to eq('completed')
      expect(body['images']).to be_an(Array)
      expect(body['images'].size).to be > 0
      expect(body['pages_converted']).to be > 0

      # Verify images were uploaded to S3
      body['images'].each_with_index do |_image_url, index|
        key = "output/page-#{index + 1}.png"

        # Check if object exists in S3
        begin
          response = s3_client.head_object(bucket: bucket_name, key: key)
          expect(response.content_type).to eq('image/png')
          expect(response.content_length).to be > 0
        rescue Aws::S3::Errors::NotFound
          raise "Expected image #{key} not found in S3"
        end
      end
    end

    it 'handles authentication failures' do
      event = {
        'body' => {
          'source' => 'http://localhost:4566/bucket/test.pdf',
          'destination' => 'http://localhost:4566/bucket/output/',
          'webhook' => 'http://localhost:3000/webhook',
          'unique_id' => 'test-123'
        }.to_json,
        'headers' => {
          'Authorization' => 'Bearer invalid-token',
          'Content-Type' => 'application/json'
        },
        'httpMethod' => 'POST',
        'path' => '/convert'
      }

      response = lambda_handler(event: event, context: {})

      expect(response[:statusCode]).to eq(401)
      body = JSON.parse(response[:body])
      expect(body['error']).to include('token')
    end
  end
end

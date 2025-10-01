# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'fileutils'
require 'base64'
require_relative '../../app'

RSpec.describe 'PDF Download Integration' do
  let(:valid_jwt_token) { 'valid.jwt.token' }
  let(:valid_s3_url) { 'https://s3.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=credential' }
  let(:destination_url) { 'https://s3.amazonaws.com/output-bucket/?X-Amz-Algorithm=AWS4-HMAC-SHA256' }
  let(:webhook_url) { 'https://example.com/webhook' }
  let(:pdf_content) do
    "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n>>\nendobj\nxref\n0 1\n0000000000 65535 f \ntrailer\n<<\n/Size 1\n/Root 1 0 R\n>>\nstartxref\n9\n%%EOF"
  end

  let(:valid_event) do
    {
      'headers' => {
        'Authorization' => "Bearer #{valid_jwt_token}"
      },
      'body' => {
        'source' => valid_s3_url,
        'destination' => destination_url,
        'webhook' => webhook_url,
        'unique_id' => 'test-123'
      }.to_json
    }
  end

  let(:context) { {} }

  before do
    WebMock.disable_net_connect!

    # Mock JWT authenticator initialization and authentication
    mock_authenticator = instance_double(JwtAuthenticator)
    allow(JwtAuthenticator).to receive(:new).and_return(mock_authenticator)
    allow(mock_authenticator).to receive(:authenticate).and_return({ authenticated: true })

    # Mock successful PDF download
    stub_request(:get, valid_s3_url)
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
    stub_request(:post, webhook_url)
      .to_return(status: 200, body: '', headers: {})

    # Ensure test image file exists
    FileUtils.mkdir_p('/tmp/test-123')
    File.write('/tmp/test-123/test-123_page_1.png',
               Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='))
  end

  after do
    WebMock.reset!
  end

  describe 'successful PDF download integration' do
    it 'processes valid request with PDF download' do
      result = lambda_handler(event: valid_event, context: context)

      expect(result[:statusCode]).to eq(200)
      expect(JSON.parse(result[:body])['message']).to eq('PDF conversion and upload completed')
      expect(JSON.parse(result[:body])['unique_id']).to eq('test-123')
      expect(JSON.parse(result[:body])['status']).to eq('completed')
    end

    it 'makes HTTP request to download PDF' do
      lambda_handler(event: valid_event, context: context)

      expect(WebMock).to have_requested(:get, valid_s3_url).once
    end
  end

  describe 'validation failures' do
    it 'rejects non-S3 source URLs' do
      invalid_event = valid_event.dup
      invalid_event['body'] = JSON.parse(invalid_event['body'])
      invalid_event['body']['source'] = 'https://example.com/file.pdf'
      invalid_event['body'] = invalid_event['body'].to_json

      result = lambda_handler(event: invalid_event, context: context)

      expect(result[:statusCode]).to eq(400)
      expect(JSON.parse(result[:body])['error']).to include('Invalid source URL')
    end

    it 'rejects non-PDF file URLs' do
      invalid_event = valid_event.dup
      invalid_event['body'] = JSON.parse(invalid_event['body'])
      invalid_event['body']['source'] = 'https://s3.amazonaws.com/bucket/file.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256'
      invalid_event['body'] = invalid_event['body'].to_json

      result = lambda_handler(event: invalid_event, context: context)

      expect(result[:statusCode]).to eq(400)
      expect(JSON.parse(result[:body])['error']).to include('Invalid source URL')
    end

    it 'rejects unsigned S3 URLs' do
      invalid_event = valid_event.dup
      invalid_event['body'] = JSON.parse(invalid_event['body'])
      invalid_event['body']['source'] = 'https://s3.amazonaws.com/bucket/file.pdf'
      invalid_event['body'] = invalid_event['body'].to_json

      result = lambda_handler(event: invalid_event, context: context)

      expect(result[:statusCode]).to eq(400)
      expect(JSON.parse(result[:body])['error']).to include('Invalid source URL')
    end
  end

  describe 'download failures' do
    it 'handles PDF download failures' do
      stub_request(:get, valid_s3_url).to_return(status: 404, body: 'Not Found')

      result = lambda_handler(event: valid_event, context: context)

      expect(result[:statusCode]).to eq(422)
      expect(JSON.parse(result[:body])['error']).to include('PDF download failed')
    end

    it 'handles network timeouts' do
      stub_request(:get, valid_s3_url).to_timeout

      result = lambda_handler(event: valid_event, context: context)

      expect(result[:statusCode]).to eq(422)
      expect(JSON.parse(result[:body])['error']).to include('PDF download failed')
    end

    it 'handles invalid PDF content' do
      stub_request(:get, valid_s3_url)
        .to_return(status: 200, body: 'Not a PDF', headers: { 'Content-Type' => 'text/plain' })

      result = lambda_handler(event: valid_event, context: context)

      expect(result[:statusCode]).to eq(422)
      expect(JSON.parse(result[:body])['error']).to include('PDF download failed')
    end
  end

  describe 'authentication integration' do
    it 'fails when authentication fails' do
      mock_authenticator = instance_double(JwtAuthenticator)
      allow(JwtAuthenticator).to receive(:new).and_return(mock_authenticator)
      allow(mock_authenticator).to receive(:authenticate)
        .and_return({ authenticated: false, error: 'Invalid token' })

      result = lambda_handler(event: valid_event, context: context)

      expect(result[:statusCode]).to eq(401)
      expect(JSON.parse(result[:body])['error']).to eq('Invalid token')
    end
  end
end

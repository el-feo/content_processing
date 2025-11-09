# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require_relative '../app'

RSpec.describe 'Lambda Handler Functions' do
  let(:response_builder) { instance_double(ResponseBuilder).as_null_object }
  let(:request_validator) { instance_double(RequestValidator).as_null_object }
  let(:jwt_authenticator) { instance_double(JwtAuthenticator).as_null_object }
  let(:pdf_downloader) { instance_double(PdfDownloader).as_null_object }
  let(:pdf_converter) { instance_double(PdfConverter).as_null_object }
  let(:image_uploader) { instance_double(ImageUploader).as_null_object }
  let(:webhook_notifier) { instance_double(WebhookNotifier).as_null_object }

  let(:event) do
    {
      'headers' => { 'Authorization' => 'Bearer valid-token' },
      'body' => JSON.generate({
                                'source' => 'https://s3.amazonaws.com/bucket/input.pdf?signed',
                                'destination' => 'https://s3.amazonaws.com/bucket/output/?signed',
                                'webhook' => 'https://example.com/webhook',
                                'unique_id' => 'test-123'
                              })
    }
  end

  let(:request_body) do
    {
      'source' => 'https://s3.amazonaws.com/bucket/input.pdf?signed',
      'destination' => 'https://s3.amazonaws.com/bucket/output/?signed',
      'webhook' => 'https://example.com/webhook',
      'unique_id' => 'test-123'
    }
  end

  before do
    allow(ResponseBuilder).to receive(:new).and_return(response_builder)
    allow(RequestValidator).to receive(:new).and_return(request_validator)
    allow(JwtAuthenticator).to receive(:new).and_return(jwt_authenticator)
    allow(PdfDownloader).to receive(:new).and_return(pdf_downloader)
    allow(PdfConverter).to receive(:new).and_return(pdf_converter)
    allow(ImageUploader).to receive(:new).and_return(image_uploader)
    allow(WebhookNotifier).to receive(:new).and_return(webhook_notifier)
    allow(FileUtils).to receive(:rm_rf)
  end

  describe '#lambda_handler' do
    context 'with successful authentication and processing' do
      let(:download_result) { { success: true, content: 'pdf-binary-content' } }
      let(:conversion_result) do
        {
          success: true,
          images: ['/tmp/test-123/page-1.png'],
          metadata: { dpi: 300 }
        }
      end
      let(:upload_result) do
        {
          success: true,
          uploaded_urls: ['https://s3.amazonaws.com/bucket/output/page-1.png']
        }
      end
      let(:success_response) do
        {
          statusCode: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({ message: 'Success' })
        }
      end

      before do
        allow(jwt_authenticator).to receive(:authenticate)
          .and_return({ authenticated: true })
        allow(request_validator).to receive(:parse_request_body)
          .and_return(request_body)
        allow(request_validator).to receive(:validate)
          .and_return(nil)
        allow(pdf_downloader).to receive(:download)
          .and_return(download_result)
        allow(pdf_converter).to receive(:convert_to_images)
          .and_return(conversion_result)
        allow(image_uploader).to receive(:upload_images_from_files)
          .and_return(upload_result)
        allow(webhook_notifier).to receive(:notify)
          .and_return({ success: true })
        allow(response_builder).to receive(:success_response)
          .and_return(success_response)
      end

      it 'returns success response' do
        result = lambda_handler(event: event)
        expect(result).to eq(success_response)
      end

      it 'authenticates the request' do
        lambda_handler(event: event)
        expect(jwt_authenticator).to have_received(:authenticate)
          .with(event['headers'])
      end

      it 'parses request body' do
        lambda_handler(event: event)
        expect(request_validator).to have_received(:parse_request_body)
          .with(event, response_builder)
      end

      it 'validates request body' do
        lambda_handler(event: event)
        expect(request_validator).to have_received(:validate)
          .with(request_body, response_builder)
      end

      it 'processes PDF conversion' do
        lambda_handler(event: event)
        expect(pdf_downloader).to have_received(:download)
        expect(pdf_converter).to have_received(:convert_to_images)
        expect(image_uploader).to have_received(:upload_images_from_files)
      end
    end

    context 'when authentication fails' do
      let(:auth_error_response) do
        {
          statusCode: 401,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({ error: 'Invalid token' })
        }
      end

      before do
        allow(jwt_authenticator).to receive(:authenticate)
          .and_return({ authenticated: false, error: 'Invalid token' })
        allow(response_builder).to receive(:authentication_error_response)
          .with('Invalid token')
          .and_return(auth_error_response)
      end

      it 'returns authentication error response' do
        result = lambda_handler(event: event)
        expect(result).to eq(auth_error_response)
      end

      it 'does not parse request body' do
        lambda_handler(event: event)
        expect(request_validator).not_to have_received(:parse_request_body)
      end

      it 'does not process conversion' do
        lambda_handler(event: event)
        expect(pdf_downloader).not_to have_received(:download)
      end
    end

    context 'when request body parsing fails' do
      let(:parse_error_response) do
        {
          statusCode: 400,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({ error: 'Invalid JSON format' })
        }
      end

      before do
        allow(jwt_authenticator).to receive(:authenticate)
          .and_return({ authenticated: true })
        allow(request_validator).to receive(:parse_request_body)
          .and_return(parse_error_response)
      end

      it 'returns parse error response' do
        result = lambda_handler(event: event)
        expect(result).to eq(parse_error_response)
      end

      it 'does not validate request' do
        lambda_handler(event: event)
        expect(request_validator).not_to have_received(:validate)
      end

      it 'does not process conversion' do
        lambda_handler(event: event)
        expect(pdf_downloader).not_to have_received(:download)
      end
    end

    context 'when request validation fails' do
      let(:validation_error_response) do
        {
          statusCode: 400,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({ error: 'Missing required fields' })
        }
      end

      before do
        allow(jwt_authenticator).to receive(:authenticate)
          .and_return({ authenticated: true })
        allow(request_validator).to receive(:parse_request_body)
          .and_return(request_body)
        allow(request_validator).to receive(:validate)
          .and_return(validation_error_response)
      end

      it 'returns validation error response' do
        result = lambda_handler(event: event)
        expect(result).to eq(validation_error_response)
      end

      it 'does not process conversion' do
        lambda_handler(event: event)
        expect(pdf_downloader).not_to have_received(:download)
      end
    end
  end

  describe '#process_pdf_conversion' do
    let(:start_time) { Time.now.to_f }
    let(:output_dir) { '/tmp/test-123' }

    context 'with successful conversion workflow' do
      let(:download_result) { { success: true, content: 'pdf-binary-content' } }
      let(:conversion_result) do
        {
          success: true,
          images: ['/tmp/test-123/page-1.png', '/tmp/test-123/page-2.png'],
          metadata: { dpi: 300, compression: 6 }
        }
      end
      let(:upload_result) do
        {
          success: true,
          uploaded_urls: [
            'https://s3.amazonaws.com/bucket/output/page-1.png',
            'https://s3.amazonaws.com/bucket/output/page-2.png'
          ]
        }
      end
      let(:success_response) do
        {
          statusCode: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({ message: 'Success' })
        }
      end

      before do
        allow(pdf_downloader).to receive(:download).and_return(download_result)
        allow(pdf_converter).to receive(:convert_to_images).and_return(conversion_result)
        allow(image_uploader).to receive(:upload_images_from_files).and_return(upload_result)
        allow(webhook_notifier).to receive(:notify).and_return({ success: true })
        allow(response_builder).to receive(:success_response).and_return(success_response)
      end

      it 'downloads PDF from source URL' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(pdf_downloader).to have_received(:download)
          .with('https://s3.amazonaws.com/bucket/input.pdf?signed')
      end

      it 'converts PDF to images' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(pdf_converter).to have_received(:convert_to_images)
          .with(hash_including(
                  pdf_content: 'pdf-binary-content',
                  output_dir: '/tmp/test-123',
                  unique_id: 'test-123'
                ))
      end

      it 'uploads images to destination' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(image_uploader).to have_received(:upload_images_from_files)
          .with('https://s3.amazonaws.com/bucket/output/?signed',
                ['/tmp/test-123/page-1.png', '/tmp/test-123/page-2.png'])
      end

      it 'sends webhook notification' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(webhook_notifier).to have_received(:notify)
          .with(hash_including(
                  webhook_url: 'https://example.com/webhook',
                  unique_id: 'test-123',
                  status: 'completed',
                  page_count: 2
                ))
      end

      it 'cleans up temporary directory' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(FileUtils).to have_received(:rm_rf).with('/tmp/test-123')
      end

      it 'returns success response' do
        result = process_pdf_conversion(request_body, start_time, response_builder)
        expect(result).to eq(success_response)
      end

      it 'passes metadata to success response' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(response_builder).to have_received(:success_response)
          .with(hash_including(metadata: { dpi: 300, compression: 6 }))
      end
    end

    context 'when PDF download fails' do
      let(:download_result) { { success: false, error: 'Network timeout' } }
      let(:error_response) do
        {
          statusCode: 422,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({ error: 'PDF download failed: Network timeout' })
        }
      end

      before do
        allow(pdf_downloader).to receive(:download).and_return(download_result)
        allow(response_builder).to receive(:error_response)
          .with(422, 'PDF download failed: Network timeout')
          .and_return(error_response)
      end

      it 'returns error response' do
        result = process_pdf_conversion(request_body, start_time, response_builder)
        expect(result).to eq(error_response)
      end

      it 'does not convert PDF' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(pdf_converter).not_to have_received(:convert_to_images)
      end

      it 'does not upload images' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(image_uploader).not_to have_received(:upload_images_from_files)
      end

      it 'cleans up output directory' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(FileUtils).to have_received(:rm_rf).with('/tmp/test-123')
      end
    end

    context 'when PDF conversion fails' do
      let(:download_result) { { success: true, content: 'pdf-binary-content' } }
      let(:conversion_result) { { success: false, error: 'Invalid PDF format' } }
      let(:error_response) do
        {
          statusCode: 422,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({ error: 'PDF conversion failed: Invalid PDF format' })
        }
      end

      before do
        allow(pdf_downloader).to receive(:download).and_return(download_result)
        allow(pdf_converter).to receive(:convert_to_images).and_return(conversion_result)
        allow(response_builder).to receive(:error_response)
          .with(422, 'PDF conversion failed: Invalid PDF format')
          .and_return(error_response)
      end

      it 'returns error response' do
        result = process_pdf_conversion(request_body, start_time, response_builder)
        expect(result).to eq(error_response)
      end

      it 'does not upload images' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(image_uploader).not_to have_received(:upload_images_from_files)
      end

      it 'cleans up output directory' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(FileUtils).to have_received(:rm_rf).with('/tmp/test-123')
      end
    end

    context 'when image upload fails' do
      let(:download_result) { { success: true, content: 'pdf-binary-content' } }
      let(:conversion_result) do
        {
          success: true,
          images: ['/tmp/test-123/page-1.png'],
          metadata: { dpi: 300 }
        }
      end
      let(:upload_result) { { success: false, error: 'S3 access denied' } }
      let(:error_response) do
        {
          statusCode: 422,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({ error: 'Image upload failed: S3 access denied' })
        }
      end

      before do
        allow(pdf_downloader).to receive(:download).and_return(download_result)
        allow(pdf_converter).to receive(:convert_to_images).and_return(conversion_result)
        allow(image_uploader).to receive(:upload_images_from_files).and_return(upload_result)
        allow(response_builder).to receive(:error_response)
          .with(422, 'Image upload failed: S3 access denied')
          .and_return(error_response)
      end

      it 'returns error response' do
        result = process_pdf_conversion(request_body, start_time, response_builder)
        expect(result).to eq(error_response)
      end

      it 'does not send webhook notification' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(webhook_notifier).not_to have_received(:notify)
      end

      it 'cleans up output directory' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(FileUtils).to have_received(:rm_rf).with('/tmp/test-123')
      end
    end

    context 'with custom DPI from environment' do
      let(:download_result) { { success: true, content: 'pdf-binary-content' } }
      let(:conversion_result) { { success: true, images: ['/tmp/test-123/page-1.png'], metadata: {} } }
      let(:upload_result) { { success: true, uploaded_urls: ['https://s3.amazonaws.com/bucket/output/page-1.png'] } }

      before do
        ENV['CONVERSION_DPI'] = '150'
        allow(pdf_downloader).to receive(:download).and_return(download_result)
        allow(pdf_converter).to receive(:convert_to_images).and_return(conversion_result)
        allow(image_uploader).to receive(:upload_images_from_files).and_return(upload_result)
        allow(webhook_notifier).to receive(:notify).and_return({ success: true })
        allow(response_builder).to receive(:success_response).and_return({})
      end

      after do
        ENV.delete('CONVERSION_DPI')
      end

      it 'uses custom DPI from environment' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(pdf_converter).to have_received(:convert_to_images)
          .with(hash_including(dpi: 150))
      end
    end

    context 'with default DPI when environment variable not set' do
      let(:download_result) { { success: true, content: 'pdf-binary-content' } }
      let(:conversion_result) { { success: true, images: ['/tmp/test-123/page-1.png'], metadata: {} } }
      let(:upload_result) { { success: true, uploaded_urls: ['https://s3.amazonaws.com/bucket/output/page-1.png'] } }

      before do
        ENV.delete('CONVERSION_DPI')
        allow(pdf_downloader).to receive(:download).and_return(download_result)
        allow(pdf_converter).to receive(:convert_to_images).and_return(conversion_result)
        allow(image_uploader).to receive(:upload_images_from_files).and_return(upload_result)
        allow(webhook_notifier).to receive(:notify).and_return({ success: true })
        allow(response_builder).to receive(:success_response).and_return({})
      end

      it 'uses default DPI of 300' do
        process_pdf_conversion(request_body, start_time, response_builder)
        expect(pdf_converter).to have_received(:convert_to_images)
          .with(hash_including(dpi: 300))
      end
    end
  end

  describe '#handle_failure' do
    let(:operation) { 'PDF download' }
    let(:result) { { success: false, error: 'Network timeout' } }
    let(:error_response) do
      {
        statusCode: 422,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({ error: 'PDF download failed: Network timeout' })
      }
    end

    before do
      allow(response_builder).to receive(:error_response)
        .with(422, 'PDF download failed: Network timeout')
        .and_return(error_response)
    end

    context 'with output directory provided' do
      let(:output_dir) { '/tmp/test-123' }

      it 'cleans up output directory' do
        handle_failure(result, response_builder, operation, output_dir)
        expect(FileUtils).to have_received(:rm_rf).with('/tmp/test-123')
      end

      it 'returns error response' do
        response = handle_failure(result, response_builder, operation, output_dir)
        expect(response).to eq(error_response)
      end

      it 'builds error response with operation name and error message' do
        handle_failure(result, response_builder, operation, output_dir)
        expect(response_builder).to have_received(:error_response)
          .with(422, 'PDF download failed: Network timeout')
      end
    end

    context 'without output directory (nil)' do
      let(:output_dir) { nil }

      it 'does not attempt cleanup' do
        handle_failure(result, response_builder, operation, output_dir)
        expect(FileUtils).not_to have_received(:rm_rf)
      end

      it 'returns error response' do
        response = handle_failure(result, response_builder, operation, output_dir)
        expect(response).to eq(error_response)
      end
    end

    context 'with different operation names' do
      it 'includes operation name in error message for conversion' do
        allow(response_builder).to receive(:error_response)
          .with(422, 'PDF conversion failed: Network timeout')
          .and_return({})
        handle_failure(result, response_builder, 'PDF conversion', nil)
        expect(response_builder).to have_received(:error_response)
          .with(422, 'PDF conversion failed: Network timeout')
      end

      it 'includes operation name in error message for upload' do
        allow(response_builder).to receive(:error_response)
          .with(422, 'Image upload failed: Network timeout')
          .and_return({})
        handle_failure(result, response_builder, 'Image upload', nil)
        expect(response_builder).to have_received(:error_response)
          .with(422, 'Image upload failed: Network timeout')
      end
    end
  end

  describe '#notify_webhook' do
    let(:webhook_url) { 'https://example.com/webhook' }
    let(:unique_id) { 'test-123' }
    let(:uploaded_urls) { ['https://s3.amazonaws.com/bucket/output/page-1.png'] }
    let(:page_count) { 1 }
    let(:start_time) { Time.now.to_f - 5.5 }

    before do
      allow(webhook_notifier).to receive(:notify).and_return({ success: true })
    end

    context 'when webhook URL is provided' do
      it 'sends webhook notification' do
        notify_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        expect(webhook_notifier).to have_received(:notify)
      end

      it 'passes all parameters to webhook notifier' do
        notify_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        expect(webhook_notifier).to have_received(:notify)
          .with(hash_including(
                  webhook_url: webhook_url,
                  unique_id: unique_id,
                  status: 'completed',
                  images: uploaded_urls,
                  page_count: page_count
                ))
      end

      it 'calculates processing time in milliseconds' do
        notify_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        expect(webhook_notifier).to have_received(:notify) do |args|
          processing_time = args[:processing_time_ms]
          expect(processing_time).to be_a(Integer)
          expect(processing_time).to be > 5000 # At least 5 seconds
        end
      end
    end

    context 'when webhook URL is nil' do
      let(:webhook_url) { nil }

      it 'does not send webhook notification' do
        notify_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        expect(webhook_notifier).not_to have_received(:notify)
      end

      it 'returns nil early' do
        result = notify_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        expect(result).to be_nil
      end
    end
  end

  describe '#send_webhook' do
    let(:webhook_url) { 'https://example.com/webhook' }
    let(:unique_id) { 'test-123' }
    let(:uploaded_urls) { ['https://s3.amazonaws.com/bucket/output/page-1.png'] }
    let(:page_count) { 1 }
    let(:start_time) { Time.now.to_f - 3.5 }

    context 'when webhook notification succeeds' do
      before do
        allow(webhook_notifier).to receive(:notify).and_return({ success: true })
      end

      it 'sends notification with correct parameters' do
        send_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        expect(webhook_notifier).to have_received(:notify)
          .with(hash_including(
                  webhook_url: webhook_url,
                  unique_id: unique_id,
                  status: 'completed',
                  images: uploaded_urls,
                  page_count: page_count
                ))
      end

      it 'calculates processing time correctly' do
        send_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        expect(webhook_notifier).to have_received(:notify) do |args|
          processing_time = args[:processing_time_ms]
          expect(processing_time).to be >= 3500
          expect(processing_time).to be < 10_000
        end
      end

      it 'does not return early' do
        result = send_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        expect(result).to be_nil
      end
    end

    context 'when webhook notification fails' do
      before do
        allow(webhook_notifier).to receive(:notify)
          .and_return({ success: false, error: 'Connection timeout' })
      end

      it 'does not raise error' do
        expect do
          send_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        end.not_to raise_error
      end

      it 'logs warning message' do
        expect do
          send_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        end.to output(/WARNING: Webhook notification failed: Connection timeout/).to_stdout
      end

      it 'continues without failing the request' do
        result = send_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
        expect(result).to be_nil
      end
    end
  end

  describe '#authenticate_request' do
    let(:event) { { 'headers' => { 'Authorization' => 'Bearer valid-token' } } }

    before do
      # Reset the memoized authenticator before each test
      instance_variable_set(:@authenticator, nil)
    end

    context 'with successful authentication' do
      before do
        allow(jwt_authenticator).to receive(:authenticate)
          .and_return({ authenticated: true, user_id: '123' })
      end

      it 'initializes authenticator with secret name' do
        authenticate_request(event)
        expect(JwtAuthenticator).to have_received(:new)
          .with('pdf-converter/jwt-secret')
      end

      it 'calls authenticate with headers' do
        authenticate_request(event)
        expect(jwt_authenticator).to have_received(:authenticate)
          .with({ 'Authorization' => 'Bearer valid-token' })
      end

      it 'returns authentication result' do
        result = authenticate_request(event)
        expect(result).to eq({ authenticated: true, user_id: '123' })
      end

      it 'memoizes authenticator instance' do
        authenticate_request(event)
        authenticate_request(event)
        expect(JwtAuthenticator).to have_received(:new).once
      end
    end

    context 'with custom JWT secret name from environment' do
      before do
        ENV['JWT_SECRET_NAME'] = 'custom-secret-name'
        allow(jwt_authenticator).to receive(:authenticate)
          .and_return({ authenticated: true })
      end

      after do
        ENV['JWT_SECRET_NAME'] = 'pdf-converter/jwt-secret'
      end

      it 'uses custom secret name from environment' do
        authenticate_request(event)
        expect(JwtAuthenticator).to have_received(:new)
          .with('custom-secret-name')
      end
    end

    context 'when headers are missing' do
      let(:event) { {} }

      before do
        allow(jwt_authenticator).to receive(:authenticate)
          .and_return({ authenticated: false, error: 'Missing Authorization header' })
      end

      it 'passes empty hash to authenticator' do
        authenticate_request(event)
        expect(jwt_authenticator).to have_received(:authenticate).with({})
      end
    end

    context 'when JwtAuthenticator::AuthenticationError is raised' do
      before do
        allow(jwt_authenticator).to receive(:authenticate)
          .and_raise(JwtAuthenticator::AuthenticationError.new('Secrets Manager unavailable'))
      end

      it 'returns authentication failure with service error' do
        result = authenticate_request(event)
        expect(result).to eq({
                               authenticated: false,
                               error: 'Authentication service unavailable'
                             })
      end

      it 'logs error message' do
        expect do
          authenticate_request(event)
        end.to output(/ERROR: Authentication service error: Secrets Manager unavailable/).to_stdout
      end
    end

    context 'when StandardError is raised' do
      before do
        allow(jwt_authenticator).to receive(:authenticate)
          .and_raise(StandardError.new('Unexpected error'))
      end

      it 'returns authentication failure with generic error' do
        result = authenticate_request(event)
        expect(result).to eq({
                               authenticated: false,
                               error: 'Authentication service error'
                             })
      end

      it 'logs error message' do
        expect do
          authenticate_request(event)
        end.to output(/ERROR: Unexpected authentication error: Unexpected error/).to_stdout
      end
    end
  end
end

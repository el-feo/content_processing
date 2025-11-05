# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'app/jwt_authenticator'
require_relative 'app/url_validator'
require_relative 'app/pdf_downloader'
require_relative 'app/pdf_converter'
require_relative 'app/image_uploader'
require_relative 'app/request_validator'
require_relative 'app/webhook_notifier'
require_relative 'app/response_builder'

def lambda_handler(event:, context: nil)
  start_time = Time.now.to_f
  # PDF to Image Converter Lambda Handler with JWT Authentication
  #
  # Expected POST body:
  # {
  #   "source": "signed_s3_url",
  #   "destination": "signed_s3_url",
  #   "webhook": "webhook_url",
  #   "unique_id": "client_id"
  # }

  # Initialize service objects
  response_builder = ResponseBuilder.new
  request_validator = RequestValidator.new

  # Authenticate the request
  auth_result = authenticate_request(event)
  return response_builder.authentication_error_response(auth_result[:error]) unless auth_result[:authenticated]

  # Parse and validate the request
  begin
    request_body = request_validator.parse_request(event)
  rescue JSON::ParserError
    return response_builder.error_response(400, 'Invalid JSON format')
  rescue StandardError
    return response_builder.error_response(400, 'Invalid request')
  end

  validation_error = request_validator.validate(request_body, response_builder)
  return validation_error if validation_error

  # Extract frequently used values
  unique_id = request_body['unique_id']
  webhook_url = request_body['webhook']
  puts "Authentication successful for unique_id: #{unique_id}"

  # Download PDF from S3
  pdf_downloader = PdfDownloader.new
  download_result = pdf_downloader.download(request_body['source'])

  unless download_result[:success]
    puts "ERROR: PDF download failed: #{download_result[:error]}"
    return response_builder.error_response(422, "PDF download failed: #{download_result[:error]}")
  end

  pdf_content = download_result[:content]
  puts "PDF downloaded successfully, size: #{pdf_content.bytesize} bytes"

  # Convert PDF to images
  output_dir = "/tmp/#{unique_id}"
  conversion_result = convert_pdf(pdf_content, output_dir, unique_id)

  unless conversion_result[:success]
    puts "ERROR: PDF conversion failed: #{conversion_result[:error]}"
    return response_builder.error_response(422, "PDF conversion failed: #{conversion_result[:error]}")
  end

  converted_images = conversion_result[:images]
  page_count = converted_images.size
  puts "PDF converted successfully: #{page_count} pages"

  # Upload images to destination
  upload_result = upload_images_to_s3(
    destination_url: request_body['destination'],
    images: converted_images
  )

  unless upload_result[:success]
    puts "ERROR: Image upload failed: #{upload_result[:error]}"
    FileUtils.rm_rf(output_dir)
    return response_builder.error_response(422, "Image upload failed: #{upload_result[:error]}")
  end

  uploaded_urls = upload_result[:uploaded_urls]
  puts "Images uploaded successfully: #{uploaded_urls.size} files"

  # Send webhook notification if provided
  send_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time) if webhook_url

  # Clean up and return success
  FileUtils.rm_rf(output_dir)
  response_builder.success_response(
    unique_id: unique_id,
    uploaded_urls: uploaded_urls,
    page_count: page_count,
    metadata: conversion_result[:metadata]
  )
end

# Converts PDF content to images using PdfConverter.
#
# @param pdf_content [String] Binary PDF content
# @param output_dir [String] Directory to save converted images
# @param unique_id [String] Unique identifier for this conversion
# @return [Hash] Conversion result with :success, :images, :metadata, or :error
def convert_pdf(pdf_content, output_dir, unique_id)
  pdf_converter = PdfConverter.new
  pdf_converter.convert_to_images(
    pdf_content: pdf_content,
    output_dir: output_dir,
    unique_id: unique_id,
    dpi: ENV['CONVERSION_DPI']&.to_i || 300
  )
end

# Sends webhook notification asynchronously (non-blocking).
#
# @param webhook_url [String] The URL to send the notification to
# @param unique_id [String] Unique identifier for this conversion
# @param uploaded_urls [Array<String>] Array of uploaded image URLs
# @param page_count [Integer] Number of pages converted
# @param start_time [Float] Start time of the conversion process
def send_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
  notifier = WebhookNotifier.new
  end_time = Time.now.to_f
  processing_time_ms = ((end_time - start_time) * 1000).to_i

  result = notifier.notify(
    webhook_url: webhook_url,
    unique_id: unique_id,
    status: 'completed',
    images: uploaded_urls,
    page_count: page_count,
    processing_time_ms: processing_time_ms
  )

  return unless result[:error]

  puts "WARNING: Webhook notification failed: #{result[:error]}"
  # Don't fail the request if webhook fails, just log it
end

def authenticate_request(event)
  # Initialize authenticator (cached after first initialization in Lambda)
  @authenticator ||= JwtAuthenticator.new(ENV['JWT_SECRET_NAME'] || 'pdf-converter/jwt-secret')

  # Get headers from the event (handle different formats)
  headers = event['headers'] || {}

  # Authenticate the request
  @authenticator.authenticate(headers)
rescue JwtAuthenticator::AuthenticationError => e
  # Handle secrets manager errors
  error_msg = e.message
  puts "ERROR: Authentication service error: #{error_msg}"
  { authenticated: false, error: 'Authentication service unavailable' }
rescue StandardError => e
  # Handle any other unexpected errors
  error_msg = e.message
  puts "ERROR: Unexpected authentication error: #{error_msg}"
  { authenticated: false, error: 'Authentication service error' }
end

def upload_images_to_s3(destination_url:, images:)
  uploader = ImageUploader.new

  # Parse the destination URL to get the base path
  uri = URI.parse(destination_url)
  uri_path = uri.path
  base_path = uri_path.end_with?('/') ? uri_path : "#{uri_path}/"

  # Generate individual URLs for each image
  image_urls = []
  image_contents = []

  images.each_with_index do |image_path, index|
    # Create URL for this specific image
    image_uri = uri.dup
    image_filename = "page-#{index + 1}.png"
    image_uri.path = "#{base_path}#{image_filename}"

    image_urls << image_uri.to_s
    image_contents << File.read(image_path, mode: 'rb')
  end

  # Upload all images concurrently
  upload_results = uploader.upload_batch(image_urls, image_contents, 'image/png')

  # Check if all uploads succeeded
  failed_uploads = upload_results.reject { |r| r[:success] }

  if failed_uploads.any?
    error_messages = failed_uploads.map { |r| r[:error] }.uniq.join(', ')
    return {
      success: false,
      error: "Failed to upload #{failed_uploads.size} images: #{error_messages}"
    }
  end

  {
    success: true,
    uploaded_urls: image_urls.map { |url| url.split('?').first }, # Return URLs without query params
    etags: upload_results.map { |r| r[:etag] }
  }
rescue StandardError => e
  {
    success: false,
    error: "Upload error: #{e.message}"
  }
end

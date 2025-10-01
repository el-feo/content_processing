# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require_relative 'jwt_authenticator'
require_relative 'url_validator'
require_relative 'pdf_downloader'
require_relative 'pdf_converter'
require_relative 'image_uploader'

def lambda_handler(event:, context:)
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

  # Authenticate the request
  auth_result = authenticate_request(event)
  return authentication_error_response(auth_result[:error]) unless auth_result[:authenticated]

  # Parse the request body
  begin
    request_body = parse_request(event)
  rescue JSON::ParserError
    return error_response(400, 'Invalid JSON format')
  rescue StandardError
    return error_response(400, 'Invalid request')
  end

  # Validate required fields
  validation_error = validate_request(request_body)
  return validation_error if validation_error

  # Log successful authentication for monitoring
  puts "Authentication successful for unique_id: #{request_body['unique_id']}"

  # Download PDF from S3
  pdf_downloader = PdfDownloader.new
  download_result = pdf_downloader.download(request_body['source'])

  unless download_result[:success]
    puts "ERROR: PDF download failed: #{download_result[:error]}"
    return error_response(422, "PDF download failed: #{download_result[:error]}")
  end

  puts "PDF downloaded successfully, size: #{download_result[:content].bytesize} bytes"

  # Convert PDF to images
  pdf_converter = PdfConverter.new
  output_dir = "/tmp/#{request_body['unique_id']}"

  conversion_result = pdf_converter.convert_to_images(
    pdf_content: download_result[:content],
    output_dir: output_dir,
    unique_id: request_body['unique_id'],
    dpi: ENV['CONVERSION_DPI']&.to_i || 300
  )

  unless conversion_result[:success]
    puts "ERROR: PDF conversion failed: #{conversion_result[:error]}"
    return error_response(422, "PDF conversion failed: #{conversion_result[:error]}")
  end

  puts "PDF converted successfully: #{conversion_result[:images].size} pages"

  # Upload images to destination
  upload_result = upload_images_to_s3(
    destination_url: request_body['destination'],
    images: conversion_result[:images],
    unique_id: request_body['unique_id']
  )

  unless upload_result[:success]
    puts "ERROR: Image upload failed: #{upload_result[:error]}"
    # Clean up before returning error
    FileUtils.rm_rf(output_dir)
    return error_response(422, "Image upload failed: #{upload_result[:error]}")
  end

  puts "Images uploaded successfully: #{upload_result[:uploaded_urls].size} files"

  # Send webhook notification if provided
  if request_body['webhook']
    webhook_result = send_webhook_notification(
      webhook_url: request_body['webhook'],
      unique_id: request_body['unique_id'],
      status: 'completed',
      images: upload_result[:uploaded_urls],
      page_count: conversion_result[:images].size,
      processing_time_ms: ((Time.now.to_f - start_time) * 1000).to_i
    )

    if webhook_result[:error]
      puts "WARNING: Webhook notification failed: #{webhook_result[:error]}"
      # Don't fail the request if webhook fails, just log it
    end
  end

  # Clean up temporary files
  FileUtils.rm_rf(output_dir)

  # Return success response
  {
    statusCode: 200,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*'
    },
    body: {
      message: 'PDF conversion and upload completed',
      images: upload_result[:uploaded_urls],
      unique_id: request_body['unique_id'],
      status: 'completed',
      pages_converted: conversion_result[:images].size,
      metadata: conversion_result[:metadata]
    }.to_json
  }
end

def parse_request(event)
  # Handle both direct invocation and API Gateway proxy format
  if event['body'].is_a?(String)
    JSON.parse(event['body'])
  elsif event['body'].is_a?(Hash)
    event['body']
  else
    event
  end
end

def validate_request(body)
  required_fields = %w[source destination webhook unique_id]

  missing_fields = required_fields - body.keys
  return error_response(400, 'Missing required fields') unless missing_fields.empty?

  # Validate unique_id format to prevent path traversal attacks
  unless body['unique_id'].match?(/\A[a-zA-Z0-9_-]+\z/)
    return error_response(400, 'Invalid unique_id format: only alphanumeric characters, underscores, ' \
                               'and hyphens are allowed')
  end

  # Initialize URL validator
  url_validator = UrlValidator.new

  # Validate source URL is a signed S3 URL for PDF
  unless url_validator.valid_s3_signed_url?(body['source'])
    return error_response(400, 'Invalid source URL: must be a signed S3 URL for PDF file')
  end

  # Validate destination URL is a signed S3 URL
  unless url_validator.valid_s3_destination_url?(body['destination'])
    return error_response(400, 'Invalid destination URL: must be a signed S3 URL')
  end

  # Validate webhook URL if provided
  if body['webhook'] && !url_validator.valid_url?(body['webhook'])
    return error_response(400, 'Invalid webhook URL format')
  end

  nil
end

def valid_url?(url_string)
  return false if url_string.nil? || url_string.empty?

  begin
    uri = URI.parse(url_string)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end
end

def error_response(status_code, message)
  {
    statusCode: status_code,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*'
    },
    body: {
      error: message
    }.to_json
  }
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
  puts "ERROR: Authentication service error: #{e.message}"
  { authenticated: false, error: 'Authentication service unavailable' }
rescue StandardError => e
  # Handle any other unexpected errors
  puts "ERROR: Unexpected authentication error: #{e.message}"
  { authenticated: false, error: 'Authentication service error' }
end

def upload_images_to_s3(destination_url:, images:, unique_id:)
  uploader = ImageUploader.new

  # Parse the destination URL to get the base path
  uri = URI.parse(destination_url)
  base_path = uri.path.end_with?('/') ? uri.path : "#{uri.path}/"

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

def send_webhook_notification(webhook_url:, unique_id:, status:, images:, page_count:, processing_time_ms:)
  uri = URI.parse(webhook_url)

  payload = {
    unique_id: unique_id,
    status: status,
    images: images,
    page_count: page_count,
    processing_time_ms: processing_time_ms
  }

  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'
  request.body = payload.to_json

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.read_timeout = 10
    http.open_timeout = 10
    http.request(request)
  end

  if response.is_a?(Net::HTTPSuccess)
    puts "Webhook notification sent successfully to #{webhook_url}"
    { success: true }
  else
    { error: "Webhook returned HTTP #{response.code}: #{response.message}" }
  end
rescue StandardError => e
  { error: "Webhook error: #{e.message}" }
end

def authentication_error_response(error_message)
  # Determine appropriate status code based on error
  status_code = if error_message.include?('service')
                  500  # Server errors (Secrets Manager issues)
                else
                  401  # Authentication failures
                end

  {
    statusCode: status_code,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*'
    },
    body: {
      error: error_message
    }.to_json
  }
end

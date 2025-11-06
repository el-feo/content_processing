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
  response_builder = ResponseBuilder.new

  # Authenticate and validate request
  auth_result = authenticate_request(event)
  return response_builder.authentication_error_response(auth_result[:error]) unless auth_result[:authenticated]

  request_body = parse_request_body(event, response_builder)
  return request_body if request_body.is_a?(Hash) && request_body[:statusCode]

  validation_error = RequestValidator.new.validate(request_body, response_builder)
  return validation_error if validation_error

  # Process the PDF conversion
  process_pdf_conversion(request_body, start_time, response_builder)
end

# Parses the request body from the event.
#
# @param event [Hash] Lambda event
# @param response_builder [ResponseBuilder] Response builder instance
# @return [Hash] Parsed request body or error response
def parse_request_body(event, response_builder)
  RequestValidator.new.parse_request(event)
rescue JSON::ParserError
  response_builder.error_response(400, 'Invalid JSON format')
rescue StandardError
  response_builder.error_response(400, 'Invalid request')
end

# Processes the complete PDF conversion workflow.
#
# @param request_body [Hash] Validated request body
# @param start_time [Float] Start time of the request
# @param response_builder [ResponseBuilder] Response builder instance
# @return [Hash] Lambda response
def process_pdf_conversion(request_body, start_time, response_builder)
  unique_id = request_body['unique_id']
  output_dir = "/tmp/#{unique_id}"

  puts "Authentication successful for unique_id: #{unique_id}"

  # Download PDF
  download_result = download_pdf(request_body['source'])
  return handle_failure(download_result, response_builder, 'PDF download', output_dir) unless download_result[:success]

  puts "PDF downloaded successfully, size: #{download_result[:content].bytesize} bytes"

  # Convert PDF to images
  conversion_result = convert_pdf(download_result[:content], output_dir, unique_id)
  unless conversion_result[:success]
    return handle_failure(conversion_result, response_builder, 'PDF conversion',
                          output_dir)
  end

  page_count = conversion_result[:images].size
  puts "PDF converted successfully: #{page_count} pages"

  # Upload images
  upload_result = upload_images(request_body['destination'], conversion_result[:images])
  return handle_failure(upload_result, response_builder, 'Image upload', output_dir) unless upload_result[:success]

  puts "Images uploaded successfully: #{upload_result[:uploaded_urls].size} files"

  # Send webhook notification
  notify_webhook(request_body['webhook'], unique_id, upload_result[:uploaded_urls], page_count, start_time)

  # Clean up and return success
  cleanup_directory(output_dir)
  response_builder.success_response(
    unique_id: unique_id,
    uploaded_urls: upload_result[:uploaded_urls],
    page_count: page_count,
    metadata: conversion_result[:metadata]
  )
end

# Downloads PDF from the source URL.
#
# @param source_url [String] Source URL for the PDF
# @return [Hash] Download result with :success, :content, or :error
def download_pdf(source_url)
  PdfDownloader.new.download(source_url)
end

# Handles operation failures consistently.
#
# @param result [Hash] Operation result hash
# @param response_builder [ResponseBuilder] Response builder instance
# @param operation [String] Name of the operation that failed
# @param output_dir [String] Optional directory to clean up
# @return [Hash] Error response
def handle_failure(result, response_builder, operation, output_dir = nil)
  error_message = result[:error]
  puts "ERROR: #{operation} failed: #{error_message}"
  cleanup_directory(output_dir) if output_dir
  response_builder.error_response(422, "#{operation} failed: #{error_message}")
end

# Cleans up temporary directory.
#
# @param directory [String] Directory path to remove
def cleanup_directory(directory)
  FileUtils.rm_rf(directory)
end

# Sends webhook notification if URL is provided.
#
# @param webhook_url [String, nil] Webhook URL
# @param unique_id [String] Unique identifier
# @param uploaded_urls [Array<String>] Uploaded image URLs
# @param page_count [Integer] Number of pages
# @param start_time [Float] Processing start time
def notify_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
  return unless webhook_url

  send_webhook(webhook_url, unique_id, uploaded_urls, page_count, start_time)
end

# Uploads images to S3 destination.
#
# @param destination_url [String] Destination URL
# @param images [Array<String>] Image file paths
# @return [Hash] Upload result
def upload_images(destination_url, images)
  upload_images_to_s3(destination_url: destination_url, images: images)
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
  puts "ERROR: Authentication service error: #{e.message}"
  { authenticated: false, error: 'Authentication service unavailable' }
rescue StandardError => e
  # Handle any other unexpected errors
  puts "ERROR: Unexpected authentication error: #{e.message}"
  { authenticated: false, error: 'Authentication service error' }
end

def upload_images_to_s3(destination_url:, images:)
  uploader = ImageUploader.new
  base_uri = parse_destination_url(destination_url)

  # Generate URLs and read image contents
  image_urls, image_contents = prepare_images_for_upload(images, base_uri)

  # Upload all images concurrently
  upload_results = uploader.upload_batch(image_urls, image_contents, 'image/png')

  # Check results
  process_upload_results(upload_results, image_urls)
rescue StandardError => e
  {
    success: false,
    error: "Upload error: #{e.message}"
  }
end

# Parses the destination URL and returns a base URI with proper path.
#
# @param destination_url [String] Destination URL
# @return [URI] Base URI with normalized path
def parse_destination_url(destination_url)
  uri = URI.parse(destination_url)
  uri_path = uri.path
  uri.path = uri_path.end_with?('/') ? uri_path : "#{uri_path}/"
  uri
end

# Prepares image URLs and contents for batch upload.
#
# @param images [Array<String>] Image file paths
# @param base_uri [URI] Base URI for uploads
# @return [Array<Array>] Two arrays: URLs and contents
def prepare_images_for_upload(images, base_uri)
  image_urls = []
  image_contents = []

  images.each_with_index do |image_path, index|
    image_uri = base_uri.dup
    image_uri.path = "#{base_uri.path}page-#{index + 1}.png"

    image_urls << image_uri.to_s
    image_contents << File.read(image_path, mode: 'rb')
  end

  [image_urls, image_contents]
end

# Processes upload results and returns success or failure hash.
#
# @param upload_results [Array<Hash>] Upload results
# @param image_urls [Array<String>] Image URLs
# @return [Hash] Result with :success, :uploaded_urls, :etags, or :error
def process_upload_results(upload_results, image_urls)
  failed_uploads = upload_results.reject { |result| result[:success] }

  if failed_uploads.any?
    error_messages = failed_uploads.map { |result| result[:error] }.uniq.join(', ')
    return {
      success: false,
      error: "Failed to upload #{failed_uploads.size} images: #{error_messages}"
    }
  end

  {
    success: true,
    uploaded_urls: strip_query_params(image_urls),
    etags: upload_results.map { |result| result[:etag] }
  }
end

# Removes query parameters from URLs.
#
# @param urls [Array<String>] URLs with query parameters
# @return [Array<String>] URLs without query parameters
def strip_query_params(urls)
  urls.map { |url| url.split('?').first }
end

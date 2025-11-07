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
require_relative 'lib/url_utils'

def lambda_handler(event:, context: nil)
  start_time = Time.now.to_f
  response_builder = ResponseBuilder.new
  request_validator = RequestValidator.new

  # Authenticate and validate request
  auth_result = authenticate_request(event)
  return response_builder.authentication_error_response(auth_result[:error]) unless auth_result[:authenticated]

  request_body = request_validator.parse_request_body(event, response_builder)
  return request_body if request_body.is_a?(Hash) && request_body[:statusCode]

  validation_error = request_validator.validate(request_body, response_builder)
  return validation_error if validation_error

  # Process the PDF conversion
  process_pdf_conversion(request_body, start_time, response_builder)
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
  download_result = PdfDownloader.new.download(request_body['source'])
  return handle_failure(download_result, response_builder, 'PDF download', output_dir) unless download_result[:success]

  pdf_content = download_result[:content]
  puts "PDF downloaded successfully, size: #{pdf_content.bytesize} bytes"

  # Convert PDF to images
  conversion_result = PdfConverter.new.convert_to_images(
    pdf_content: pdf_content,
    output_dir: output_dir,
    unique_id: unique_id,
    dpi: ENV['CONVERSION_DPI']&.to_i || 300
  )
  unless conversion_result[:success]
    return handle_failure(conversion_result, response_builder, 'PDF conversion',
                          output_dir)
  end

  images = conversion_result[:images]
  page_count = images.size
  puts "PDF converted successfully: #{page_count} pages"

  # Upload images
  upload_result = ImageUploader.new.upload_images_from_files(request_body['destination'], images)
  return handle_failure(upload_result, response_builder, 'Image upload', output_dir) unless upload_result[:success]

  uploaded_urls = upload_result[:uploaded_urls]
  puts "Images uploaded successfully: #{uploaded_urls.size} files"

  # Send webhook notification
  notify_webhook(request_body['webhook'], unique_id, uploaded_urls, page_count, start_time)

  # Clean up and return success
  FileUtils.rm_rf(output_dir)
  response_builder.success_response(
    unique_id: unique_id,
    uploaded_urls: uploaded_urls,
    page_count: page_count,
    metadata: conversion_result[:metadata]
  )
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
  FileUtils.rm_rf(output_dir) if output_dir
  response_builder.error_response(422, "#{operation} failed: #{error_message}")
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

  error_message = result[:error]
  return unless error_message

  puts "WARNING: Webhook notification failed: #{error_message}"
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

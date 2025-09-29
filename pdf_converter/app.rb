# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require_relative 'jwt_authenticator'
require_relative 'url_validator'
require_relative 'pdf_downloader'
require_relative 'pdf_converter'

def lambda_handler(event:, context:)
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

  # TODO: Upload images to destination
  # TODO: Send webhook notification

  # Clean up temporary files
  FileUtils.rm_rf(output_dir) if Dir.exist?(output_dir)

  # Return success response
  {
    statusCode: 200,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*'
    },
    body: {
      message: 'PDF conversion completed',
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
    return error_response(400, 'Invalid unique_id format: only alphanumeric characters, underscores, and hyphens are allowed')
  end

  # Initialize URL validator
  url_validator = UrlValidator.new

  # Validate source URL is a signed S3 URL for PDF
  unless url_validator.valid_s3_signed_url?(body['source'])
    return error_response(400, 'Invalid source URL: must be a signed S3 URL for PDF file')
  end

  # Validate destination and webhook URLs
  %w[destination webhook].each do |field|
    unless url_validator.valid_url?(body[field])
      return error_response(400, "Invalid #{field} URL format")
    end
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

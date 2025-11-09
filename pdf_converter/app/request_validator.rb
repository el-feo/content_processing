# frozen_string_literal: true

require 'json'
require_relative 'url_validator'

# RequestValidator handles parsing and validation of incoming Lambda requests.
# It validates required fields, unique_id format, and URL formats for source,
# destination, and webhook URLs.
class RequestValidator
  # List of fields that must be present in the request body
  REQUIRED_FIELDS = %w[source destination webhook unique_id].freeze

  # Regex pattern for validating unique_id format
  # Only alphanumeric characters, underscores, and hyphens are allowed
  UNIQUE_ID_PATTERN = /\A[a-zA-Z0-9_-]+\z/

  def initialize
    @url_validator = UrlValidator.new
  end

  # Parses the incoming Lambda event and extracts the request body.
  # Handles both direct invocation and API Gateway proxy format.
  #
  # @param event [Hash] The Lambda event object
  # @return [Hash] The parsed request body
  # @raise [JSON::ParserError] If the body is not valid JSON
  def parse_request(event)
    if event['body'].is_a?(String)
      JSON.parse(event['body'])
    elsif event['body'].is_a?(Hash)
      event['body']
    else
      event
    end
  end

  # Parses the request body from the event with error handling.
  # Returns either the parsed body or an error response.
  #
  # @param event [Hash] Lambda event
  # @param response_builder [ResponseBuilder] Response builder instance
  # @return [Hash] Parsed request body or error response
  def parse_request_body(event, response_builder)
    parse_request(event)
  rescue JSON::ParserError
    response_builder.error_response(400, 'Invalid JSON format')
  rescue StandardError
    response_builder.error_response(400, 'Invalid request')
  end

  # Validates the request body against all requirements.
  # Returns nil if validation passes, or an error response hash if validation fails.
  #
  # @param body [Hash] The parsed request body
  # @param response_builder [ResponseBuilder] The response builder to use for error responses
  # @return [Hash, nil] Error response hash if validation fails, nil if valid
  def validate(body, response_builder)
    # Check for missing required fields (including nil values)
    missing_fields = REQUIRED_FIELDS.select { |field| body[field].nil? }
    return response_builder.error_response(400, 'Missing required fields') unless missing_fields.empty?

    # Validate unique_id format to prevent path traversal attacks
    unless body['unique_id'].match?(UNIQUE_ID_PATTERN)
      return response_builder.error_response(
        400,
        'Invalid unique_id format: only alphanumeric characters, underscores, and hyphens are allowed'
      )
    end

    # Validate source URL is a signed S3 URL for PDF
    unless @url_validator.valid_s3_signed_url?(body['source'])
      return response_builder.error_response(400, 'Invalid source URL: must be a signed S3 URL for PDF file')
    end

    # Validate destination URL is a signed S3 URL
    unless @url_validator.valid_s3_destination_url?(body['destination'])
      return response_builder.error_response(400, 'Invalid destination URL: must be a signed S3 URL')
    end

    # Validate webhook URL if provided
    if body['webhook'] && !@url_validator.valid_url?(body['webhook'])
      return response_builder.error_response(400, 'Invalid webhook URL format')
    end

    # All validations passed
    nil
  end
end

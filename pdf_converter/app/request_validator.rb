# frozen_string_literal: true

require 'json'
require_relative 'url_validator'

# RequestValidator handles parsing and validation of incoming Lambda requests.
# It validates required fields, S3 bucket/key format, credentials, and unique_id format.
class RequestValidator
  # Regex pattern for validating unique_id format
  # Only alphanumeric characters, underscores, and hyphens are allowed
  UNIQUE_ID_PATTERN = /\A[a-zA-Z0-9_-]+\z/

  # S3 bucket name validation (AWS rules)
  # 3-63 characters, lowercase, numbers, dots, hyphens
  BUCKET_NAME_PATTERN = /\A[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]\z/

  # S3 key validation - not empty and reasonable length
  MAX_KEY_LENGTH = 1024

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
    # Validate unique_id first (required and format)
    return response_builder.error_response(400, 'Missing required field: unique_id') if body['unique_id'].nil?

    unless body['unique_id'].match?(UNIQUE_ID_PATTERN)
      return response_builder.error_response(
        400,
        'Invalid unique_id format: only alphanumeric characters, underscores, and hyphens are allowed'
      )
    end

    # Validate source
    source_error = validate_source(body['source'])
    return response_builder.error_response(400, source_error) if source_error

    # Validate destination
    dest_error = validate_destination(body['destination'])
    return response_builder.error_response(400, dest_error) if dest_error

    # Validate credentials
    creds_error = validate_credentials(body['credentials'])
    return response_builder.error_response(400, creds_error) if creds_error

    # Validate webhook URL if provided (optional)
    if body['webhook'] && !body['webhook'].empty? && !@url_validator.valid_url?(body['webhook'])
      return response_builder.error_response(400, 'Invalid webhook URL format')
    end

    # All validations passed
    nil
  end

  private

  # Validates the source object
  def validate_source(source)
    return 'Missing required field: source' if source.nil?
    return 'source must be an object' unless source.is_a?(Hash)

    return 'source.bucket is required' if source['bucket'].nil? || source['bucket'].empty?
    return 'source.key is required' if source['key'].nil? || source['key'].empty?

    return 'Invalid source.bucket format' unless source['bucket'].match?(BUCKET_NAME_PATTERN)
    return 'source.key is too long' if source['key'].length > MAX_KEY_LENGTH
    return 'source.key must end with .pdf' unless source['key'].downcase.end_with?('.pdf')

    nil
  end

  # Validates the destination object
  def validate_destination(destination)
    return 'Missing required field: destination' if destination.nil?
    return 'destination must be an object' unless destination.is_a?(Hash)

    return 'destination.bucket is required' if destination['bucket'].nil? || destination['bucket'].empty?
    return 'destination.prefix is required' if destination['prefix'].nil?

    return 'Invalid destination.bucket format' unless destination['bucket'].match?(BUCKET_NAME_PATTERN)
    return 'destination.prefix is too long' if destination['prefix'].length > MAX_KEY_LENGTH

    nil
  end

  # Validates the credentials object
  def validate_credentials(credentials)
    return 'Missing required field: credentials' if credentials.nil?
    return 'credentials must be an object' unless credentials.is_a?(Hash)

    if credentials['accessKeyId'].nil? || credentials['accessKeyId'].empty?
      return 'credentials.accessKeyId is required'
    end
    if credentials['secretAccessKey'].nil? || credentials['secretAccessKey'].empty?
      return 'credentials.secretAccessKey is required'
    end
    if credentials['sessionToken'].nil? || credentials['sessionToken'].empty?
      return 'credentials.sessionToken is required'
    end

    # Basic format validation for access key ID (should start with ASIA for temp creds)
    unless credentials['accessKeyId'].start_with?('ASIA', 'AKIA')
      return 'Invalid credentials.accessKeyId format'
    end

    nil
  end
end

require 'json'
require 'net/http'
require 'uri'
require_relative 'jwt_authenticator'

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
  unless auth_result[:authenticated]
    return authentication_error_response(auth_result[:error])
  end

  # Parse the request body
  begin
    request_body = parse_request(event)
  rescue JSON::ParserError
    return error_response(400, "Invalid JSON format")
  rescue StandardError
    return error_response(400, "Invalid request")
  end

  # Validate required fields
  validation_error = validate_request(request_body)
  return validation_error if validation_error

  # Log successful authentication for monitoring
  puts "Authentication successful for unique_id: #{request_body['unique_id']}"

  # Return accepted response for async processing
  {
    statusCode: 202,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*'
    },
    body: {
      message: "PDF conversion request received",
      unique_id: request_body['unique_id'],
      status: "accepted"
    }.to_json
  }
end

private

def parse_request(event)
  # Handle both direct invocation and API Gateway proxy format
  body = if event['body'].is_a?(String)
    JSON.parse(event['body'])
  elsif event['body'].is_a?(Hash)
    event['body']
  else
    event
  end

  body
end

def validate_request(body)
  required_fields = %w[source destination webhook unique_id]

  missing_fields = required_fields - body.keys
  unless missing_fields.empty?
    return error_response(400, "Missing required fields")
  end

  # Validate URLs
  %w[source destination webhook].each do |field|
    unless valid_url?(body[field])
      return error_response(400, "Invalid URL format")
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
  begin
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

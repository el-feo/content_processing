require 'json'
require 'net/http'
require 'uri'

def lambda_handler(event:, context:)
  # PDF to Image Converter Lambda Handler
  #
  # Expected POST body:
  # {
  #   "source": "signed_s3_url",
  #   "destination": "signed_s3_url",
  #   "webhook": "webhook_url",
  #   "unique_id": "client_id"
  # }

  # Parse the request body
  begin
    request_body = parse_request(event)
  rescue JSON::ParserError => e
    return error_response(400, "Invalid JSON format")
  rescue StandardError => e
    return error_response(400, "Invalid request")
  end

  # Validate required fields
  validation_error = validate_request(request_body)
  return validation_error if validation_error

  # For now, return a simple success response
  # This will be expanded to include actual PDF processing
  {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json'
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
      'Content-Type': 'application/json'
    },
    body: {
      error: message
    }.to_json
  }
end
# frozen_string_literal: true

require 'json'

# ResponseBuilder constructs standardized Lambda responses with proper headers.
# Handles both success and error responses with consistent structure.
class ResponseBuilder
  # Standard CORS headers included in all responses
  CORS_HEADERS = {
    'Content-Type' => 'application/json',
    'Access-Control-Allow-Origin' => '*'
  }.freeze

  # Builds a standard error response.
  #
  # @param status_code [Integer] The HTTP status code (e.g., 400, 422, 500)
  # @param message [String] The error message to return
  # @return [Hash] Lambda response hash with statusCode, headers, and body
  def error_response(status_code, message)
    {
      statusCode: status_code,
      headers: CORS_HEADERS,
      body: { error: message }.to_json
    }
  end

  # Builds an authentication error response with appropriate status code.
  # Determines whether to return 401 (auth failure) or 500 (service error).
  #
  # @param error_message [String] The authentication error message
  # @return [Hash] Lambda response hash with statusCode, headers, and body
  def authentication_error_response(error_message)
    # Determine appropriate status code based on error type
    status_code = if error_message.include?('service')
                    500  # Server errors (Secrets Manager issues)
                  else
                    401  # Authentication failures
                  end

    {
      statusCode: status_code,
      headers: CORS_HEADERS,
      body: { error: error_message }.to_json
    }
  end

  # Builds a success response for completed PDF conversion.
  #
  # @param unique_id [String] The unique identifier for this conversion request
  # @param uploaded_urls [Array<String>] Array of uploaded image URLs
  # @param page_count [Integer] Number of pages converted
  # @param metadata [Hash] Additional metadata from the conversion process
  # @return [Hash] Lambda response hash with statusCode, headers, and body
  def success_response(unique_id:, uploaded_urls:, page_count:, metadata:)
    {
      statusCode: 200,
      headers: CORS_HEADERS,
      body: {
        message: 'PDF conversion and upload completed',
        images: uploaded_urls,
        unique_id: unique_id,
        status: 'completed',
        pages_converted: page_count,
        metadata: metadata
      }.to_json
    }
  end
end

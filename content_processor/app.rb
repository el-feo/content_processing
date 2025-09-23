require 'json'
require_relative 'lib/authentication'

class ContentProcessor
  include Authentication

  def self.lambda_handler(event:, context:)
    # Wrap the main handler with authentication
    Authentication.require_authentication do |authenticated_event, context|
      new.process_content(authenticated_event, context)
    end.call(event, context)
  end

  def process_content(event, context)
    # Extract authentication info
    user_id = authenticated_user_id(event)
    user_permissions = authenticated_user_permissions(event)
    correlation_id = correlation_id(event)

    # Check if user has required permission for content processing
    require_permission(event, 'process')

    # Your existing content processing logic here
    # This is where PDF processing, S3 operations would go

    {
      statusCode: 200,
      body: {
        message: "Content processed successfully",
        user_id: user_id,
        correlation_id: correlation_id,
        processed_at: Time.now.iso8601
      }.to_json,
      headers: {
        'Content-Type' => 'application/json',
        'X-Correlation-ID' => correlation_id
      }
    }
  rescue JwtValidation::Error => e
    correlation_id = correlation_id(event) || JwtValidation.generate_correlation_id
    JwtValidation.create_error_response(e.message, correlation_id)
  rescue => e
    correlation_id = correlation_id(event) || JwtValidation.generate_correlation_id
    puts "Unexpected error: #{e.message}"
    JwtValidation.create_error_response('Internal server error', correlation_id)
  end
end

# For backward compatibility and AWS Lambda runtime
def lambda_handler(event:, context:)
  ContentProcessor.lambda_handler(event: event, context: context)
end

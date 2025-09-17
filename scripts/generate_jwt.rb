#!/usr/bin/env ruby

require 'jwt'
require 'json'
require 'aws-sdk-secretsmanager'

# Function to get JWT secret from Secrets Manager
def get_jwt_secret_from_aws
  secret_name = ENV['JWT_SECRET_NAME'] || 'pdf-processor/jwt-secret'
  region = ENV['AWS_REGION'] || 'us-east-1'

  client = Aws::SecretsManager::Client.new(region: region)

  begin
    response = client.get_secret_value(secret_id: secret_name)

    if response.secret_string
      secret_data = JSON.parse(response.secret_string)
      secret_data['jwt_secret'] || secret_data['secret'] || response.secret_string
    else
      Base64.decode64(response.secret_binary)
    end
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException => e
    puts "Secret #{secret_name} not found: #{e.message}"
    puts "Falling back to environment variable or default"
    nil
  rescue => e
    puts "Error retrieving secret from AWS: #{e.message}"
    puts "Falling back to environment variable or default"
    nil
  end
end

# Try to get secret from AWS Secrets Manager first, fall back to env var or default
jwt_secret = get_jwt_secret_from_aws || ENV['JWT_SECRET'] || 'change-me-to-secure-secret'

if jwt_secret == 'change-me-to-secure-secret'
  puts "WARNING: Using default secret. For production, store the secret in AWS Secrets Manager"
  puts ""
end

# Create payload with some claims
payload = {
  sub: '1234567890',
  name: 'Test User',
  iat: Time.now.to_i,
  exp: Time.now.to_i + 3600  # Token expires in 1 hour
}

# Generate token
token = JWT.encode(payload, jwt_secret, 'HS256')

puts "Generated JWT Token:"
puts token
puts "\nDecoded payload:"
puts JSON.pretty_generate(payload)
puts "\nUse this in your Authorization header:"
puts "Bearer #{token}"
puts "\nExample curl command:"
puts <<~CURL
  curl -X POST https://your-api-endpoint/Prod/process \\
    -H "Authorization: Bearer #{token}" \\
    -H "Content-Type: application/json" \\
    -d '{
      "source": "https://your-s3-signed-url-for-pdf",
      "destination": "https://your-s3-signed-url-for-output",
      "webhook": "https://your-webhook-url"
    }'
CURL
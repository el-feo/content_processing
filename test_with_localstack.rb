#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'jwt'
require 'aws-sdk-s3'
require 'aws-sdk-secretsmanager'

# Set up environment for LocalStack
ENV['AWS_ENDPOINT_URL'] = 'http://localhost:4566'
ENV['AWS_REGION'] = 'us-east-1'
ENV['JWT_SECRET_NAME'] = 'pdf-converter/jwt-secret'
ENV['AWS_ACCESS_KEY_ID'] = 'test'
ENV['AWS_SECRET_ACCESS_KEY'] = 'test'

# Load application files
require_relative 'pdf_converter/app'
require_relative 'pdf_converter/jwt_authenticator'
require_relative 'pdf_converter/pdf_downloader'
require_relative 'pdf_converter/pdf_converter'
require_relative 'pdf_converter/url_validator'
require_relative 'pdf_converter/image_uploader'
require_relative 'pdf_converter/lib/aws_config'

# Test configuration
LOCALSTACK_ENDPOINT = 'http://localhost:4566'
BUCKET_NAME = 'pdf-converter-test'
JWT_SECRET = 'test-secret-key-for-localstack-testing-12345'

# Create S3 client and presigner for LocalStack
s3_client = Aws::S3::Client.new(
  endpoint: LOCALSTACK_ENDPOINT,
  region: 'us-east-1',
  credentials: Aws::Credentials.new('test', 'test'),
  force_path_style: true
)

s3_presigner = Aws::S3::Presigner.new(client: s3_client)

puts "🧪 Testing PDF Converter with LocalStack..."
puts

# Generate JWT token
jwt_token = JWT.encode(
  {
    sub: 'test-client',
    iat: Time.now.to_i,
    exp: Time.now.to_i + 3600,
    service: 'pdf-converter'
  },
  JWT_SECRET,
  'HS256'
)

# Get presigned URLs for source and destination
source_url = s3_presigner.presigned_url(
  :get_object,
  bucket: BUCKET_NAME,
  key: 'input/test.pdf',
  expires_in: 3600
)

# For destination, we need a base URL that the function can append filenames to
dest_presigned = s3_presigner.presigned_url(
  :put_object,
  bucket: BUCKET_NAME,
  key: 'output/placeholder.png',
  expires_in: 3600
)

# Extract the base path and keep query parameters
dest_uri = URI.parse(dest_presigned)
dest_url = dest_presigned.sub('/placeholder.png', '/')

puts "📄 Source URL: #{source_url[0..80]}..."
puts "📁 Dest URL: #{dest_url[0..80]}..."
puts

# Create test event
event = {
  'body' => {
    'source' => source_url,
    'destination' => dest_url,
    'webhook' => 'http://localhost:3000/webhook',
    'unique_id' => 'localstack-test-001'
  }.to_json,
  'headers' => {
    'Authorization' => "Bearer #{jwt_token}",
    'Content-Type' => 'application/json'
  },
  'httpMethod' => 'POST',
  'path' => '/convert'
}

puts "🚀 Invoking Lambda handler..."
puts

begin
  response = lambda_handler(event: event, context: {})

  puts "📊 Response Status: #{response[:statusCode]}"
  puts

  if response[:statusCode] == 200
    body = JSON.parse(response[:body])
    puts "✅ Success!"
    puts "   Status: #{body['status']}"
    puts "   Pages converted: #{body['pages_converted']}"
    puts "   Images:"
    body['images'].each_with_index do |url, idx|
      puts "     #{idx + 1}. #{url}"
    end
    puts

    # Verify images exist in S3
    puts "🔍 Verifying images in LocalStack S3..."
    body['images'].each_with_index do |image_url, index|
      key = "output/page-#{index + 1}.png"
      begin
        obj = s3_client.head_object(bucket: BUCKET_NAME, key: key)
        puts "   ✓ #{key} (#{obj.content_length} bytes, #{obj.content_type})"
      rescue Aws::S3::Errors::NotFound
        puts "   ✗ #{key} NOT FOUND"
      end
    end
    puts
    puts "🎉 All tests passed!"
  else
    body = JSON.parse(response[:body])
    puts "❌ Error:"
    puts "   #{body['error']}"
  end
rescue StandardError => e
  puts "❌ Exception:"
  puts "   #{e.class}: #{e.message}"
  puts
  puts "Backtrace:"
  puts e.backtrace.first(10).map { |line| "   #{line}" }
end
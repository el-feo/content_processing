#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'aws-sdk-sts', '~> 1'
end

require 'json'
require 'optparse'

# Script to generate temporary AWS STS credentials for PDF Converter client testing
# Assumes the IAM role and returns credentials that can be used to call the API

class StsCredentialGenerator
  EXTERNAL_ID = 'pdf-converter-client'
  DURATION_SECONDS = 900 # 15 minutes

  def initialize(role_arn:, region: 'us-east-1', session_name: nil)
    @role_arn = role_arn
    @region = region
    @session_name = session_name || "pdf-converter-#{Time.now.to_i}"
    @sts_client = Aws::STS::Client.new(region: @region)
  end

  def generate
    puts "Assuming role: #{@role_arn}"
    puts "External ID: #{EXTERNAL_ID}"
    puts "Session name: #{@session_name}"
    puts "Duration: #{DURATION_SECONDS} seconds (#{DURATION_SECONDS / 60} minutes)"
    puts ""

    response = @sts_client.assume_role(
      role_arn: @role_arn,
      role_session_name: @session_name,
      external_id: EXTERNAL_ID,
      duration_seconds: DURATION_SECONDS
    )

    credentials = response.credentials

    {
      'accessKeyId' => credentials.access_key_id,
      'secretAccessKey' => credentials.secret_access_key,
      'sessionToken' => credentials.session_token,
      'expiration' => credentials.expiration.iso8601
    }
  rescue Aws::STS::Errors::AccessDenied => e
    raise "Access denied: #{e.message}. Ensure your AWS credentials have permission to assume the role."
  rescue Aws::Errors::ServiceError => e
    raise "AWS Error: #{e.message}"
  end
end

# Parse options
options = {
  role_arn: nil,
  region: 'us-east-1',
  format: 'pretty',
  session_name: nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.separator ""
  opts.separator "Generate temporary AWS STS credentials for PDF Converter client testing"
  opts.separator ""
  opts.separator "Options:"

  opts.on("-a", "--role-arn ARN", "IAM role ARN to assume (required)") do |v|
    options[:role_arn] = v
  end

  opts.on("-r", "--region REGION", "AWS region (default: us-east-1)") do |v|
    options[:region] = v
  end

  opts.on("-s", "--session-name NAME", "Role session name (default: pdf-converter-TIMESTAMP)") do |v|
    options[:session_name] = v
  end

  opts.on("-f", "--format FORMAT", "Output format: pretty, json, curl (default: pretty)") do |v|
    unless %w[pretty json curl].include?(v)
      puts "Error: Invalid format '#{v}'. Must be one of: pretty, json, curl"
      exit 1
    end
    options[:format] = v
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    puts ""
    puts "Example:"
    puts "  #{$PROGRAM_NAME} \\"
    puts "    --role-arn arn:aws:iam::123456789012:role/PdfConverterClientRole"
    puts ""
    puts "  # Generate credentials as JSON"
    puts "  #{$PROGRAM_NAME} \\"
    puts "    --role-arn arn:aws:iam::123456789012:role/PdfConverterClientRole \\"
    puts "    --format json"
    puts ""
    puts "  # Generate curl command template"
    puts "  #{$PROGRAM_NAME} \\"
    puts "    --role-arn arn:aws:iam::123456789012:role/PdfConverterClientRole \\"
    puts "    --format curl"
    exit
  end
end.parse!

# Validate
if options[:role_arn].nil?
  puts "Error: --role-arn is required"
  puts "Run with --help for usage information"
  exit 1
end

begin
  generator = StsCredentialGenerator.new(
    role_arn: options[:role_arn],
    region: options[:region],
    session_name: options[:session_name]
  )

  credentials = generator.generate

  case options[:format]
  when 'json'
    puts JSON.pretty_generate(credentials)

  when 'curl'
    puts "# Copy this curl command and replace placeholders with your values:"
    puts "curl -X POST https://YOUR_API_ENDPOINT/convert \\"
    puts "  -H \"Authorization: Bearer YOUR_JWT_TOKEN\" \\"
    puts "  -H \"Content-Type: application/json\" \\"
    puts "  -d '{"
    puts "    \"source\": {"
    puts "      \"bucket\": \"YOUR_SOURCE_BUCKET\","
    puts "      \"key\": \"path/to/your/file.pdf\""
    puts "    },"
    puts "    \"destination\": {"
    puts "      \"bucket\": \"YOUR_DEST_BUCKET\","
    puts "      \"prefix\": \"output/\""
    puts "    },"
    puts "    \"credentials\": {"
    puts "      \"accessKeyId\": \"#{credentials['accessKeyId']}\","
    puts "      \"secretAccessKey\": \"#{credentials['secretAccessKey']}\","
    puts "      \"sessionToken\": \"#{credentials['sessionToken']}\""
    puts "    },"
    puts "    \"unique_id\": \"test-#{Time.now.to_i}\","
    puts "    \"webhook\": \"https://YOUR_WEBHOOK_URL\" (optional)"
    puts "  }'"
    puts ""
    puts "# Credentials expire at: #{credentials['expiration']}"

  else # pretty
    puts "=" * 80
    puts "✅ STS Credentials Generated Successfully"
    puts "=" * 80
    puts ""
    puts "Credentials (expires at #{credentials['expiration']}):"
    puts ""
    puts "JSON Payload for API Request:"
    puts ""
    puts "{"
    puts "  \"source\": {"
    puts "    \"bucket\": \"YOUR_SOURCE_BUCKET\","
    puts "    \"key\": \"path/to/your/file.pdf\""
    puts "  },"
    puts "  \"destination\": {"
    puts "    \"bucket\": \"YOUR_DEST_BUCKET\","
    puts "    \"prefix\": \"output/\""
    puts "  },"
    puts "  \"credentials\": {"
    puts "    \"accessKeyId\": \"#{credentials['accessKeyId']}\","
    puts "    \"secretAccessKey\": \"#{credentials['secretAccessKey']}\","
    puts "    \"sessionToken\": \"#{credentials['sessionToken']}\""
    puts "  },"
    puts "  \"unique_id\": \"test-#{Time.now.to_i}\","
    puts "  \"webhook\": \"https://your-webhook-url.com\" (optional)"
    puts "}"
    puts ""
    puts "=" * 80
    puts ""
    puts "Use --format json for JSON output"
    puts "Use --format curl for a ready-to-use curl command"
  end

rescue StandardError => e
  puts "Error: #{e.message}"
  puts ""
  puts "Troubleshooting:"
  puts "  1. Ensure AWS credentials are configured (run 'aws configure')"
  puts "  2. Verify the role ARN is correct"
  puts "  3. Check that your AWS user/role has permission to assume the target role"
  puts "  4. Verify the ExternalId '#{StsCredentialGenerator::EXTERNAL_ID}' matches the role's trust policy"
  exit 1
end

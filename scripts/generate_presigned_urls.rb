#!/usr/bin/env ruby
# frozen_string_literal: true

require 'aws-sdk-s3'
require 'optparse'
require 'json'

# Script to generate pre-signed S3 URLs for testing the PDF Converter API
# Uses local AWS credentials from ~/.aws/credentials or environment variables

class PresignedUrlGenerator
  DEFAULT_EXPIRATION = 3600 # 1 hour

  def initialize(bucket:, region: 'us-east-1', expiration: DEFAULT_EXPIRATION)
    @bucket = bucket
    @region = region
    @expiration = expiration
    @s3_client = Aws::S3::Client.new(region: @region)
  end

  # Generate a pre-signed GET URL for downloading the source PDF
  def generate_source_url(key)
    signer = Aws::S3::Presigner.new(client: @s3_client)
    signer.presigned_url(
      :get_object,
      bucket: @bucket,
      key: key,
      expires_in: @expiration
    )
  end

  # Generate a pre-signed PUT URL for uploading converted images
  # The key should be a prefix/folder path ending with /
  def generate_destination_url(prefix)
    # Ensure prefix ends with / for folder-style access
    prefix = prefix.end_with?('/') ? prefix : "#{prefix}/"

    signer = Aws::S3::Presigner.new(client: @s3_client)
    signer.presigned_url(
      :put_object,
      bucket: @bucket,
      key: "#{prefix}placeholder.png", # Example key, actual keys will be unique_id-N.png
      expires_in: @expiration
    ).gsub('placeholder.png', '') # Remove placeholder to get base URL
  end

  # Generate both URLs and return as a hash
  def generate_urls(source_key:, destination_prefix:, unique_id: 'test')
    {
      source: generate_source_url(source_key),
      destination: generate_destination_url(destination_prefix),
      unique_id: unique_id,
      bucket: @bucket,
      region: @region,
      expiration: @expiration
    }
  end
end

# Parse command line options
options = {
  region: 'us-east-1',
  expiration: PresignedUrlGenerator::DEFAULT_EXPIRATION,
  unique_id: "test-#{Time.now.to_i}",
  output_format: 'pretty'
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} --bucket BUCKET --source-key KEY --dest-prefix PREFIX [options]"
  opts.separator ""
  opts.separator "Generate pre-signed S3 URLs for testing the PDF Converter API"
  opts.separator ""
  opts.separator "Required arguments:"

  opts.on("-b", "--bucket BUCKET", "S3 bucket name") do |v|
    options[:bucket] = v
  end

  opts.on("-s", "--source-key KEY", "S3 key for source PDF (e.g., 'pdfs/test.pdf')") do |v|
    options[:source_key] = v
  end

  opts.on("-d", "--dest-prefix PREFIX", "S3 prefix for destination images (e.g., 'output/')") do |v|
    options[:dest_prefix] = v
  end

  opts.separator ""
  opts.separator "Optional arguments:"

  opts.on("-r", "--region REGION", "AWS region (default: us-east-1)") do |v|
    options[:region] = v
  end

  opts.on("-e", "--expiration SECONDS", Integer, "URL expiration in seconds (default: 3600)") do |v|
    options[:expiration] = v
  end

  opts.on("-u", "--unique-id ID", "Unique ID for this conversion (default: test-TIMESTAMP)") do |v|
    options[:unique_id] = v
  end

  opts.on("-f", "--format FORMAT", "Output format: pretty, json, curl (default: pretty)") do |v|
    options[:output_format] = v
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Validate required arguments
unless options[:bucket] && options[:source_key] && options[:dest_prefix]
  puts "Error: --bucket, --source-key, and --dest-prefix are required"
  puts "Run with --help for usage information"
  exit 1
end

# Generate URLs
begin
  generator = PresignedUrlGenerator.new(
    bucket: options[:bucket],
    region: options[:region],
    expiration: options[:expiration]
  )

  urls = generator.generate_urls(
    source_key: options[:source_key],
    destination_prefix: options[:dest_prefix],
    unique_id: options[:unique_id]
  )

  # Output based on format
  case options[:output_format]
  when 'json'
    puts JSON.pretty_generate(urls)
  when 'curl'
    # Output a ready-to-use curl command (requires JWT token to be added)
    puts "# Copy this curl command and replace YOUR_JWT_TOKEN with an actual token"
    puts "curl -X POST YOUR_API_ENDPOINT \\"
    puts "  -H \"Authorization: Bearer YOUR_JWT_TOKEN\" \\"
    puts "  -H \"Content-Type: application/json\" \\"
    puts "  -d '{"
    puts "    \"source\": \"#{urls[:source]}\","
    puts "    \"destination\": \"#{urls[:destination]}\","
    puts "    \"unique_id\": \"#{urls[:unique_id]}\""
    puts "  }'"
  else # pretty
    puts "=" * 80
    puts "Pre-signed S3 URLs Generated"
    puts "=" * 80
    puts ""
    puts "Source URL (GET):"
    puts "  #{urls[:source]}"
    puts ""
    puts "Destination URL (PUT):"
    puts "  #{urls[:destination]}"
    puts ""
    puts "Details:"
    puts "  Bucket:      #{urls[:bucket]}"
    puts "  Region:      #{urls[:region]}"
    puts "  Unique ID:   #{urls[:unique_id]}"
    puts "  Expires in:  #{urls[:expiration]} seconds (#{urls[:expiration] / 60} minutes)"
    puts ""
    puts "JSON Payload for API:"
    puts JSON.pretty_generate({
      source: urls[:source],
      destination: urls[:destination],
      unique_id: urls[:unique_id]
    })
    puts ""
    puts "=" * 80
  end

rescue Aws::Errors::ServiceError => e
  puts "AWS Error: #{e.message}"
  puts ""
  puts "Make sure you have:"
  puts "  1. AWS credentials configured (run 'aws configure')"
  puts "  2. Permissions to access S3 in region #{options[:region]}"
  exit 1
rescue StandardError => e
  puts "Error: #{e.message}"
  exit 1
end

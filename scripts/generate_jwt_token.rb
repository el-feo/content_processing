#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'jwt', '~> 2.7'
  gem 'aws-sdk-secretsmanager', '~> 1'
end

require 'optparse'

# Script to generate JWT tokens for testing the PDF Converter API
# Can retrieve secret from AWS Secrets Manager or use a provided secret

class JwtTokenGenerator
  DEFAULT_EXPIRATION = 3600 # 1 hour

  def initialize(secret:)
    @secret = secret
  end

  def generate_token(subject: 'test-user', expiration: DEFAULT_EXPIRATION)
    payload = {
      sub: subject,
      iat: Time.now.to_i,
      exp: Time.now.to_i + expiration
    }

    JWT.encode(payload, @secret, 'HS256')
  end

  # Retrieve secret from AWS Secrets Manager
  def self.retrieve_secret_from_aws(secret_name:, region: 'us-east-1')
    client = Aws::SecretsManager::Client.new(region: region)
    response = client.get_secret_value(secret_id: secret_name)
    response.secret_string
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException
    raise "Secret '#{secret_name}' not found in region #{region}"
  rescue Aws::Errors::ServiceError => e
    raise "AWS error retrieving secret: #{e.message}"
  end
end

# Parse command line options
options = {
  region: 'us-east-1',
  expiration: JwtTokenGenerator::DEFAULT_EXPIRATION,
  subject: 'test-user',
  secret_name: 'pdf-converter/jwt-secret'
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.separator ""
  opts.separator "Generate JWT tokens for testing the PDF Converter API"
  opts.separator ""
  opts.separator "The script will retrieve the JWT secret from AWS Secrets Manager by default."
  opts.separator "Alternatively, provide a secret directly with --secret."
  opts.separator ""
  opts.separator "Options:"

  opts.on("-s", "--secret SECRET", "JWT secret (if not using AWS Secrets Manager)") do |v|
    options[:secret] = v
  end

  opts.on("-n", "--secret-name NAME", "AWS Secrets Manager secret name (default: pdf-converter/jwt-secret)") do |v|
    options[:secret_name] = v
  end

  opts.on("-r", "--region REGION", "AWS region (default: us-east-1)") do |v|
    options[:region] = v
  end

  opts.on("-e", "--expiration SECONDS", Integer, "Token expiration in seconds (default: 3600)") do |v|
    options[:expiration] = v
  end

  opts.on("-u", "--subject SUBJECT", "Token subject/user identifier (default: test-user)") do |v|
    options[:subject] = v
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Get the secret
begin
  secret = if options[:secret]
             options[:secret]
           else
             puts "Retrieving secret from AWS Secrets Manager..."
             JwtTokenGenerator.retrieve_secret_from_aws(
               secret_name: options[:secret_name],
               region: options[:region]
             )
           end

  # Generate token
  generator = JwtTokenGenerator.new(secret: secret)
  token = generator.generate_token(
    subject: options[:subject],
    expiration: options[:expiration]
  )

  # Output
  puts "=" * 80
  puts "JWT Token Generated"
  puts "=" * 80
  puts ""
  puts "Token:"
  puts token
  puts ""
  puts "Authorization Header:"
  puts "Authorization: Bearer #{token}"
  puts ""
  puts "Details:"
  puts "  Subject:     #{options[:subject]}"
  puts "  Expires in:  #{options[:expiration]} seconds (#{options[:expiration] / 60} minutes)"
  puts "  Issued at:   #{Time.now}"
  puts "  Expires at:  #{Time.now + options[:expiration]}"
  puts ""
  puts "=" * 80

rescue StandardError => e
  puts "Error: #{e.message}"
  puts ""
  puts "Make sure you have:"
  puts "  1. AWS credentials configured (run 'aws configure')"
  puts "  2. Access to the secret in AWS Secrets Manager"
  puts "  3. Or provide a secret directly with --secret"
  exit 1
end

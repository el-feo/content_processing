#!/usr/bin/env ruby

require 'json'
require 'aws-sdk-secretsmanager'
require 'securerandom'
require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: manage_secret.rb [options]"

  opts.on("-c", "--create", "Create or update the JWT secret in AWS Secrets Manager") do
    options[:action] = :create
  end

  opts.on("-r", "--retrieve", "Retrieve the JWT secret from AWS Secrets Manager") do
    options[:action] = :retrieve
  end

  opts.on("-g", "--generate", "Generate a new secure secret value") do
    options[:generate] = true
  end

  opts.on("-s", "--secret SECRET", "Specific secret value to use (instead of generating)") do |s|
    options[:secret] = s
  end

  opts.on("-n", "--name NAME", "Secret name in AWS (default: pdf-processor/jwt-secret)") do |n|
    options[:name] = n
  end

  opts.on("--region REGION", "AWS region (default: us-east-1)") do |r|
    options[:region] = r
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

secret_name = options[:name] || ENV['JWT_SECRET_NAME'] || 'pdf-processor/jwt-secret'
region = options[:region] || ENV['AWS_REGION'] || 'us-east-1'

client = Aws::SecretsManager::Client.new(region: region)

case options[:action]
when :create
  # Generate or use provided secret
  secret_value = if options[:generate]
    SecureRandom.hex(32)
  elsif options[:secret]
    options[:secret]
  else
    puts "Please provide a secret value with -s or use -g to generate one"
    exit 1
  end

  secret_data = {
    jwt_secret: secret_value,
    created_at: Time.now.iso8601,
    description: "JWT secret for PDF processor Lambda function"
  }

  begin
    # Try to update existing secret
    response = client.put_secret_value(
      secret_id: secret_name,
      secret_string: secret_data.to_json
    )
    puts "Secret updated successfully!"
    puts "Secret ARN: #{response.arn}"
    puts "Version ID: #{response.version_id}"
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException
    # Secret doesn't exist, create it
    response = client.create_secret(
      name: secret_name,
      description: "JWT Secret for authenticating PDF processor requests",
      secret_string: secret_data.to_json
    )
    puts "Secret created successfully!"
    puts "Secret ARN: #{response.arn}"
    puts "Version ID: #{response.version_id}"
  rescue => e
    puts "Error managing secret: #{e.message}"
    exit 1
  end

  if options[:generate]
    puts "\nGenerated secret value: #{secret_value}"
    puts "\nIMPORTANT: Save this value securely. You won't be able to see it again from the console."
  end

when :retrieve
  begin
    response = client.get_secret_value(secret_id: secret_name)

    if response.secret_string
      secret_data = JSON.parse(response.secret_string)
      puts "Secret retrieved successfully!"
      puts "Secret Name: #{secret_name}"
      puts "Version ID: #{response.version_id}"
      puts "Created/Updated: #{secret_data['created_at']}" if secret_data['created_at']
      puts "\nSecret Value: #{secret_data['jwt_secret']}"
    else
      puts "Binary secret: #{Base64.decode64(response.secret_binary)}"
    end
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException => e
    puts "Secret not found: #{secret_name}"
    puts "Error: #{e.message}"
    exit 1
  rescue => e
    puts "Error retrieving secret: #{e.message}"
    exit 1
  end

else
  puts "Please specify an action: --create or --retrieve"
  puts "Use --help for more information"
  exit 1
end
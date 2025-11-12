#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'aws-sdk-iam', '~> 1'
  gem 'aws-sdk-sts', '~> 1'
end

require 'json'
require 'optparse'

# Script to create IAM role for PDF Converter clients
# This role allows clients to access S3 buckets for PDF conversion

class IamRoleSetup
  ROLE_NAME = 'PdfConverterClientRole'
  EXTERNAL_ID = 'pdf-converter-client'

  def initialize(account_id:, source_buckets:, dest_buckets:)
    @account_id = account_id
    @source_buckets = source_buckets
    @dest_buckets = dest_buckets
    @iam_client = Aws::IAM::Client.new
  end

  def setup
    puts "Setting up IAM role: #{ROLE_NAME}"
    puts "Account ID: #{@account_id}"
    puts "Source buckets: #{@source_buckets.join(', ')}"
    puts "Destination buckets: #{@dest_buckets.join(', ')}"
    puts ""

    # Check if role exists
    if role_exists?
      puts "⚠️  Role #{ROLE_NAME} already exists"
      print "Delete and recreate? (y/N): "
      response = gets.chomp.downcase
      if response == 'y'
        delete_role
      else
        puts "Exiting without changes"
        return
      end
    end

    # Create role
    create_role
    attach_policy

    role_arn = "arn:aws:iam::#{@account_id}:role/#{ROLE_NAME}"

    puts ""
    puts "=" * 80
    puts "✅ IAM Role Setup Complete"
    puts "=" * 80
    puts ""
    puts "Role ARN:"
    puts "  #{role_arn}"
    puts ""
    puts "External ID (required when assuming role):"
    puts "  #{EXTERNAL_ID}"
    puts ""
    puts "To assume this role:"
    puts "  aws sts assume-role \\"
    puts "    --role-arn #{role_arn} \\"
    puts "    --role-session-name pdf-converter-session \\"
    puts "    --external-id #{EXTERNAL_ID} \\"
    puts "    --duration-seconds 900"
    puts ""
    puts "Or use: ./scripts/generate_sts_credentials.rb --role-arn #{role_arn}"
    puts ""
    puts "=" * 80
  end

  private

  def role_exists?
    @iam_client.get_role(role_name: ROLE_NAME)
    true
  rescue Aws::IAM::Errors::NoSuchEntity
    false
  end

  def delete_role
    puts "Deleting existing role..."

    # Delete inline policies
    @iam_client.list_role_policies(role_name: ROLE_NAME).policy_names.each do |policy_name|
      @iam_client.delete_role_policy(role_name: ROLE_NAME, policy_name: policy_name)
    end

    # Detach managed policies
    @iam_client.list_attached_role_policies(role_name: ROLE_NAME).attached_policies.each do |policy|
      @iam_client.detach_role_policy(role_name: ROLE_NAME, policy_arn: policy.policy_arn)
    end

    # Delete role
    @iam_client.delete_role(role_name: ROLE_NAME)
    puts "✅ Existing role deleted"
  end

  def create_role
    puts "Creating IAM role..."

    trust_policy = {
      "Version" => "2012-10-17",
      "Statement" => [
        {
          "Effect" => "Allow",
          "Principal" => {
            "AWS" => "arn:aws:iam::#{@account_id}:root"
          },
          "Action" => "sts:AssumeRole",
          "Condition" => {
            "StringEquals" => {
              "sts:ExternalId" => EXTERNAL_ID
            }
          }
        }
      ]
    }

    @iam_client.create_role(
      role_name: ROLE_NAME,
      assume_role_policy_document: trust_policy.to_json,
      description: 'Role for PDF Converter clients to access S3'
    )

    puts "✅ Role created"
  end

  def attach_policy
    puts "Attaching permissions policy..."

    statements = []

    # Add read permissions for source buckets
    @source_buckets.each do |bucket|
      statements << {
        "Sid" => "ReadSource#{bucket.gsub(/[^a-zA-Z0-9]/, '')}",
        "Effect" => "Allow",
        "Action" => "s3:GetObject",
        "Resource" => "arn:aws:s3:::#{bucket}/*"
      }
    end

    # Add write permissions for destination buckets
    @dest_buckets.each do |bucket|
      statements << {
        "Sid" => "WriteDest#{bucket.gsub(/[^a-zA-Z0-9]/, '')}",
        "Effect" => "Allow",
        "Action" => "s3:PutObject",
        "Resource" => "arn:aws:s3:::#{bucket}/*"
      }
    end

    permissions_policy = {
      "Version" => "2012-10-17",
      "Statement" => statements
    }

    @iam_client.put_role_policy(
      role_name: ROLE_NAME,
      policy_name: 'S3AccessPolicy',
      policy_document: permissions_policy.to_json
    )

    puts "✅ Policy attached"
  end
end

# Get current account ID
def get_account_id
  sts = Aws::STS::Client.new
  sts.get_caller_identity.account
end

# Parse options
options = {
  source_buckets: [],
  dest_buckets: []
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.separator ""
  opts.separator "Create IAM role for PDF Converter client S3 access"
  opts.separator ""
  opts.separator "Options:"

  opts.on("-s", "--source-bucket BUCKET", "Source S3 bucket (can specify multiple times)") do |v|
    options[:source_buckets] << v
  end

  opts.on("-d", "--dest-bucket BUCKET", "Destination S3 bucket (can specify multiple times)") do |v|
    options[:dest_buckets] << v
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    puts ""
    puts "Example:"
    puts "  #{$PROGRAM_NAME} \\"
    puts "    --source-bucket my-pdfs \\"
    puts "    --dest-bucket my-converted-images"
    exit
  end
end.parse!

# Validate
if options[:source_buckets].empty? || options[:dest_buckets].empty?
  puts "Error: At least one source bucket and one destination bucket required"
  puts "Run with --help for usage information"
  exit 1
end

begin
  account_id = get_account_id
  setup = IamRoleSetup.new(
    account_id: account_id,
    source_buckets: options[:source_buckets],
    dest_buckets: options[:dest_buckets]
  )
  setup.setup
rescue Aws::Errors::ServiceError => e
  puts "AWS Error: #{e.message}"
  puts ""
  puts "Make sure you have:"
  puts "  1. AWS credentials configured (run 'aws configure')"
  puts "  2. IAM permissions to create roles and policies"
  exit 1
rescue StandardError => e
  puts "Error: #{e.message}"
  exit 1
end

# frozen_string_literal: true

require 'aws-sdk-secretsmanager'

module AwsConfig
  def self.secrets_manager_client
    config = {
      region: ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION'] || 'us-east-1'
    }

    # Support LocalStack and custom endpoints
    if ENV['AWS_ENDPOINT_URL']
      puts "DEBUG: Using custom endpoint: #{ENV['AWS_ENDPOINT_URL']}"
      config[:endpoint] = ENV['AWS_ENDPOINT_URL']
      config[:credentials] = Aws::Credentials.new('test', 'test')
      config[:force_path_style] = true  # Required for LocalStack S3
    end

    Aws::SecretsManager::Client.new(config)
  end

  def self.region
    ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION'] || 'us-east-1'
  end

  def self.jwt_secret_name
    ENV['JWT_SECRET_NAME'] || 'pdf-converter/jwt-secret'
  end
end

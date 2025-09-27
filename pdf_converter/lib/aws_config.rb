require 'aws-sdk-secretsmanager'

module AwsConfig
  def self.secrets_manager_client
    @secrets_manager_client ||= Aws::SecretsManager::Client.new(
      region: ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION'] || 'us-east-1'
    )
  end

  def self.region
    ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION'] || 'us-east-1'
  end

  def self.jwt_secret_name
    ENV['JWT_SECRET_NAME'] || 'pdf-converter/jwt-secret'
  end
end
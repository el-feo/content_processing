# frozen_string_literal: true

require 'jwt'

# JWT test helper methods for generating test tokens
module JwtHelper
  # Generate a valid JWT token for testing
  #
  # @param secret [String] The secret key to sign the token
  # @param payload [Hash] Optional payload overrides
  # @return [String] The encoded JWT token
  def generate_valid_token(secret: 'test-secret', payload: {})
    default_payload = {
      user_id: '123',
      exp: Time.now.to_i + 3600 # Expires in 1 hour
    }
    JWT.encode(default_payload.merge(payload), secret, 'HS256')
  end

  # Generate an expired JWT token for testing
  #
  # @param secret [String] The secret key to sign the token
  # @param payload [Hash] Optional payload overrides
  # @return [String] The encoded JWT token
  def generate_expired_token(secret: 'test-secret', payload: {})
    default_payload = {
      user_id: '123',
      exp: Time.now.to_i - 3600 # Expired 1 hour ago
    }
    JWT.encode(default_payload.merge(payload), secret, 'HS256')
  end

  # Generate a JWT token with an invalid signature
  #
  # @param wrong_secret [String] The wrong secret key to sign the token
  # @param payload [Hash] Optional payload overrides
  # @return [String] The encoded JWT token with invalid signature
  def generate_invalid_signature_token(wrong_secret: 'wrong-secret', payload: {})
    default_payload = {
      user_id: '123',
      exp: Time.now.to_i + 3600
    }
    JWT.encode(default_payload.merge(payload), wrong_secret, 'HS256')
  end

  # Mock AWS Secrets Manager to return a specific secret
  #
  # @param secret_name [String] The name of the secret
  # @param secret_value [String] The value to return
  # @return [void]
  def mock_secrets_manager(secret_name:, secret_value:)
    secrets_client = instance_double(Aws::SecretsManager::Client)
    allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
    allow(secrets_client).to receive(:get_secret_value)
      .with(secret_id: secret_name)
      .and_return(double(secret_string: secret_value))
  end

  # Mock AWS Secrets Manager to raise an error
  #
  # @param secret_name [String] The name of the secret
  # @param error_class [Class] The error class to raise
  # @return [void]
  def mock_secrets_manager_error(secret_name:, error_class: Aws::SecretsManager::Errors::ResourceNotFoundException)
    secrets_client = instance_double(Aws::SecretsManager::Client)
    allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
    allow(secrets_client).to receive(:get_secret_value)
      .with(secret_id: secret_name)
      .and_raise(error_class.new(nil, nil))
  end
end

# Include JWT helper in RSpec
RSpec.configure do |config|
  config.include JwtHelper
end

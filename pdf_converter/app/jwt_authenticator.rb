# frozen_string_literal: true

require 'jwt'
require 'aws-sdk-secretsmanager'
require 'json'
require 'logger'

# JwtAuthenticator handles JWT token authentication for Lambda requests,
# retrieving secrets from AWS Secrets Manager and validating tokens
class JwtAuthenticator
  # AuthenticationError is raised when secret retrieval fails
  class AuthenticationError < StandardError; end

  attr_reader :logger

  def initialize(secret_name)
    @secret_name = secret_name
    @logger = Logger.new($stdout)
    @logger.level = ENV['LOG_LEVEL'] || Logger::INFO
    @secret = nil
    retrieve_secret
  end

  def authenticate(headers)
    token = extract_token(headers)

    if token.nil?
      error_msg = if headers.key?('Authorization') || headers.key?('authorization')
                    'Invalid Bearer token format'
                  else
                    'Missing Authorization header'
                  end
      log_error("Authentication failed: #{error_msg}")
      return { authenticated: false, error: error_msg }
    end

    validation_result = validate_token(token)

    if validation_result[:valid]
      log_debug('Authentication successful')
      { authenticated: true, payload: validation_result[:payload] }
    else
      log_error("Authentication failed: #{validation_result[:error]}")
      { authenticated: false, error: validation_result[:error] }
    end
  end

  def extract_token(headers)
    return nil if headers.nil?

    auth_header = headers['Authorization'] || headers['authorization']
    return nil if auth_header.nil?

    parts = auth_header.split
    return nil unless parts.length == 2 && parts[0].downcase == 'bearer'

    parts[1]
  end

  def validate_token(token)
    return { valid: false, error: 'No token provided' } if token.nil? || token.empty?

    begin
      decoded_payload = JWT.decode(
        token,
        @secret,
        true,
        { algorithm: 'HS256' }
      )

      { valid: true, payload: decoded_payload[0] }
    rescue JWT::ExpiredSignature
      { valid: false, error: 'Token has expired' }
    rescue JWT::VerificationError
      { valid: false, error: 'Invalid signature' }
    rescue JWT::DecodeError
      { valid: false, error: 'Malformed token' }
    rescue StandardError => e
      { valid: false, error: "Token validation error: #{e.message}" }
    end
  end

  def log_error(message)
    @logger&.error(message)
  end

  def log_debug(message)
    @logger&.debug(message)
  end

  private

  # Retrieves the JWT secret from AWS Secrets Manager
  def retrieve_secret
    client = Aws::SecretsManager::Client.new(build_client_config)
    secret_response = client.get_secret_value(secret_id: @secret_name)
    @secret = secret_response.secret_string

    log_debug('Successfully retrieved JWT secret from Secrets Manager')
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException
    handle_secret_error("Secret '#{@secret_name}' not found")
  rescue Aws::SecretsManager::Errors::ServiceError => e
    handle_secret_error("AWS service error - #{e.message}")
  rescue StandardError => e
    handle_secret_error(e.message)
  end

  # Builds the AWS Secrets Manager client configuration
  # Supports LocalStack for testing by configuring custom endpoints and credentials
  def build_client_config
    config = { region: ENV['AWS_REGION'] || 'us-east-1' }

    return config unless ENV['AWS_ENDPOINT_URL']

    # Configure for LocalStack testing environment
    config.merge(
      endpoint: ENV['AWS_ENDPOINT_URL'],
      access_key_id: ENV['AWS_ACCESS_KEY_ID'] || 'test',
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'] || 'test',
      ssl_verify_peer: false
    )
  end

  # Handles errors during secret retrieval by logging and raising AuthenticationError
  def handle_secret_error(message)
    error_msg = "Failed to retrieve JWT secret: #{message}"
    log_error(error_msg)
    raise AuthenticationError, error_msg
  end
end

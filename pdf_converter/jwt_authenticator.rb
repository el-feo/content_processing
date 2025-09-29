# frozen_string_literal: true

require 'jwt'
require 'aws-sdk-secretsmanager'
require 'json'
require 'logger'

class JwtAuthenticator
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

  def retrieve_secret
    client_config = {
      region: ENV['AWS_REGION'] || 'us-east-1'
    }

    # Add endpoint URL for LocalStack if provided
    if ENV['AWS_ENDPOINT_URL']
      client_config[:endpoint] = ENV['AWS_ENDPOINT_URL']
      # For LocalStack, use dummy credentials and disable SSL verification
      client_config[:access_key_id] = ENV['AWS_ACCESS_KEY_ID'] || 'test'
      client_config[:secret_access_key] = ENV['AWS_SECRET_ACCESS_KEY'] || 'test'
      client_config[:ssl_verify_peer] = false
    end

    client = Aws::SecretsManager::Client.new(client_config)

    secret_response = client.get_secret_value(secret_id: @secret_name)
    @secret = secret_response.secret_string

    log_debug('Successfully retrieved JWT secret from Secrets Manager')
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException
    error_msg = "Failed to retrieve JWT secret: Secret '#{@secret_name}' not found"
    log_error(error_msg)
    raise AuthenticationError, error_msg
  rescue Aws::SecretsManager::Errors::ServiceError => e
    error_msg = "Failed to retrieve JWT secret: AWS service error - #{e.message}"
    log_error(error_msg)
    raise AuthenticationError, error_msg
  rescue StandardError => e
    error_msg = "Failed to retrieve JWT secret: #{e.message}"
    log_error(error_msg)
    raise AuthenticationError, error_msg
  end
end

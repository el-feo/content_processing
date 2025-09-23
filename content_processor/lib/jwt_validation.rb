require 'jwt'
require 'openssl'
require 'securerandom'
require 'aws-sdk-cloudwatch'

module JwtValidation
  class Error < StandardError; end
  class ExpiredTokenError < Error; end
  class InvalidTokenError < Error; end
  class MissingTokenError < Error; end

  ALGORITHM = 'RS256'.freeze
  DEFAULT_GRACE_PERIOD = 300 # 5 minutes in seconds

  module_function

  def validate_token(token, public_key, grace_period: DEFAULT_GRACE_PERIOD)
    raise MissingTokenError, 'Token is required' if token.nil? || token.empty?

    begin
      # First decode without verification to check expiry with grace period
      unverified_payload = JWT.decode(token, nil, false)[0]

      # Check token expiry with grace period
      if token_expired_beyond_grace?(unverified_payload, grace_period)
        record_metric('AuthenticationFailure', 'ExpiredToken')
        raise ExpiredTokenError, 'Token has expired beyond grace period'
      end

      # Now decode with verification
      payload, header = JWT.decode(token, public_key, true, { algorithm: ALGORITHM })

      # Extract claims
      claims = extract_claims(payload)

      record_metric('AuthenticationSuccess', 'ValidToken')

      {
        valid: true,
        claims: claims,
        header: header,
        correlation_id: generate_correlation_id
      }

    rescue JWT::ExpiredSignature
      record_metric('AuthenticationFailure', 'ExpiredToken')
      raise ExpiredTokenError, 'Token has expired'
    rescue JWT::VerificationError
      record_metric('AuthenticationFailure', 'InvalidSignature')
      raise InvalidTokenError, 'Token signature verification failed'
    rescue JWT::DecodeError => e
      record_metric('AuthenticationFailure', 'MalformedToken')
      raise InvalidTokenError, "Token decode error: #{e.message}"
    end
  end

  def extract_token_from_headers(headers)
    # Support both Authorization Bearer and X-Auth-Token headers
    auth_header = headers['Authorization'] || headers['authorization']
    x_auth_token = headers['X-Auth-Token'] || headers['x-auth-token']

    if auth_header&.start_with?('Bearer ')
      auth_header.split(' ', 2).last
    elsif x_auth_token
      x_auth_token
    else
      nil
    end
  end

  def extract_claims(payload)
    {
      user_id: payload['user_id'],
      permissions: payload['permissions'] || [],
      exp: payload['exp'],
      iat: payload['iat'],
      sub: payload['sub'],
      iss: payload['iss'],
      aud: payload['aud']
    }
  end

  def token_expired_beyond_grace?(payload, grace_period)
    return false unless payload['exp']

    token_exp = Time.at(payload['exp'])
    time_since_expiry = Time.now - token_exp

    time_since_expiry > grace_period
  end

  def generate_correlation_id
    SecureRandom.uuid
  end

  def record_metric(metric_name, reason = nil)
    return unless aws_cloudwatch_enabled?

    begin
      cloudwatch = Aws::CloudWatch::Client.new

      dimensions = [
        {
          name: 'Service',
          value: 'ContentProcessor'
        }
      ]

      if reason
        dimensions << {
          name: 'Reason',
          value: reason
        }
      end

      cloudwatch.put_metric_data({
        namespace: 'ContentProcessor/Authentication',
        metric_data: [
          {
            metric_name: metric_name,
            dimensions: dimensions,
            value: 1,
            unit: 'Count',
            timestamp: Time.now
          }
        ]
      })
    rescue => e
      # Log error but don't fail authentication due to metrics issues
      puts "Failed to record CloudWatch metric: #{e.message}"
    end
  end

  def aws_cloudwatch_enabled?
    # Check if running in AWS environment or if metrics are explicitly enabled
    ENV['AWS_REGION'] || ENV['ENABLE_CLOUDWATCH_METRICS'] == 'true'
  end

  def create_error_response(error_message, correlation_id = nil)
    {
      statusCode: 401,
      body: {
        error: 'Unauthorized',
        message: error_message,
        correlation_id: correlation_id || generate_correlation_id,
        timestamp: Time.now.iso8601
      }.to_json,
      headers: {
        'Content-Type' => 'application/json'
      }
    }
  end

  def get_public_key
    # Load public key from environment variable or file
    public_key_content = ENV['JWT_PUBLIC_KEY']

    if public_key_content
      OpenSSL::PKey::RSA.new(public_key_content)
    else
      raise InvalidTokenError, 'JWT public key not configured'
    end
  end
end
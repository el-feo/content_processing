require_relative 'jwt_validation'

module Authentication
  def self.included(base)
    base.extend(ClassMethods)
  end

  def self.require_authentication(grace_period: JwtValidation::DEFAULT_GRACE_PERIOD)
    ->(event, context) do
        begin
          # Extract headers from API Gateway event
          headers = event['headers'] || {}

          # Extract token from headers
          token = JwtValidation.extract_token_from_headers(headers)

          if token.nil?
            correlation_id = JwtValidation.generate_correlation_id
            JwtValidation.record_metric('AuthenticationFailure', 'MissingToken')
            return JwtValidation.create_error_response('Missing authentication token', correlation_id)
          end

          # Get public key for validation
          public_key = JwtValidation.get_public_key

          # Validate the token
          validation_result = JwtValidation.validate_token(token, public_key, grace_period: grace_period)

          # Add authentication info to event for handler use
          event['auth'] = validation_result[:claims]
          event['correlation_id'] = validation_result[:correlation_id]

          # Call the original handler with authenticated event
          yield(event, context)

        rescue JwtValidation::MissingTokenError => e
          correlation_id = JwtValidation.generate_correlation_id
          JwtValidation.create_error_response(e.message, correlation_id)
        rescue JwtValidation::ExpiredTokenError => e
          correlation_id = JwtValidation.generate_correlation_id
          JwtValidation.create_error_response(e.message, correlation_id)
        rescue JwtValidation::InvalidTokenError => e
          correlation_id = JwtValidation.generate_correlation_id
          JwtValidation.create_error_response(e.message, correlation_id)
        rescue => e
          correlation_id = JwtValidation.generate_correlation_id
          JwtValidation.record_metric('AuthenticationFailure', 'UnexpectedError')
          JwtValidation.create_error_response('Authentication error occurred', correlation_id)
        end
      end
    end
  end

  def self.with_authentication(grace_period: JwtValidation::DEFAULT_GRACE_PERIOD, &block)
    require_authentication(grace_period: grace_period).call(&block)
  end

  module ClassMethods

  # Instance methods for use within handlers
  def authenticated_user_id(event)
    event.dig('auth', 'user_id')
  end

  def authenticated_user_permissions(event)
    event.dig('auth', 'permissions') || []
  end

  def correlation_id(event)
    event['correlation_id']
  end

  def has_permission?(event, required_permission)
    user_permissions = authenticated_user_permissions(event)
    user_permissions.include?(required_permission)
  end

  def require_permission(event, required_permission)
    unless has_permission?(event, required_permission)
      correlation_id = event['correlation_id'] || JwtValidation.generate_correlation_id
      JwtValidation.record_metric('AuthorizationFailure', 'InsufficientPermissions')
      raise JwtValidation::Error, "Insufficient permissions. Required: #{required_permission}"
    end
  end
end
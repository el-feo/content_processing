# frozen_string_literal: true

require 'timeout'
require 'socket'
require 'openssl'

# RetryHandler provides reusable retry logic with exponential backoff
# for handling transient failures in network operations
module RetryHandler
  # Default configuration
  DEFAULT_MAX_ATTEMPTS = 3
  DEFAULT_RETRY_DELAY_BASE = 1 # seconds
  RETRYABLE_HTTP_CODES = [500, 502, 503, 504].freeze

  # Retryable exception types
  RETRYABLE_EXCEPTIONS = [
    Timeout::Error,
    Errno::ECONNREFUSED,
    SocketError,
    OpenSSL::SSL::SSLError
  ].freeze

  # Non-retryable exception types that should fail immediately
  NON_RETRYABLE_EXCEPTIONS = [
    NoMemoryError
  ].freeze

  class RetryError < StandardError; end

  # Executes a block with retry logic
  # @param max_attempts [Integer] Maximum number of retry attempts
  # @param delay_base [Integer] Base delay in seconds for exponential backoff
  # @param logger [Logger, nil] Optional logger for retry messages
  # @yield The block to execute with retry logic
  # @return The result of the block execution
  # @raise RetryError if all retry attempts are exhausted
  def self.with_retry(max_attempts: DEFAULT_MAX_ATTEMPTS, delay_base: DEFAULT_RETRY_DELAY_BASE, logger: nil)
    attempt = 1
    last_error = nil

    while attempt <= max_attempts
      begin
        return yield(attempt)
      rescue *NON_RETRYABLE_EXCEPTIONS => e
        # Don't retry non-retryable errors, fail immediately
        raise e
      rescue StandardError => e
        last_error = e

        # Check if we should retry this error
        raise e unless retryable_error?(e)

        # Check if we have attempts remaining
        raise RetryError, "#{e.message} after #{max_attempts} attempts" if attempt >= max_attempts

        # Log the retry attempt
        log_retry(logger, attempt, e.message)

        # Wait before retrying with exponential backoff
        wait_before_retry(attempt, delay_base)

        attempt += 1
      end
    end

    # This should never be reached, but included for safety
    raise RetryError, "#{last_error&.message || 'Unknown error'} after #{max_attempts} attempts"
  end

  # Determines if an error is retryable
  # @param error [StandardError] The error to check
  # @return [Boolean] true if the error should trigger a retry
  def self.retryable_error?(error)
    # Check if it's a retryable exception type
    return true if RETRYABLE_EXCEPTIONS.any? { |exception_class| error.is_a?(exception_class) }

    # Check for retryable HTTP status codes
    if error.message.match(/HTTP (\d+):/)
      status_code = ::Regexp.last_match(1).to_i
      return RETRYABLE_HTTP_CODES.include?(status_code)
    end

    false
  end

  # Waits before retrying with exponential backoff
  # @param attempt [Integer] Current attempt number
  # @param delay_base [Integer] Base delay in seconds
  def self.wait_before_retry(attempt, delay_base)
    delay = delay_base * (2**(attempt - 1)) # Exponential backoff: 1s, 2s, 4s, 8s...
    sleep(delay)
  end

  # Logs retry attempt information
  # @param logger [Logger, nil] Logger instance or nil
  # @param attempt [Integer] Current attempt number
  # @param error_message [String] Error message
  def self.log_retry(logger, attempt, error_message)
    message = "Retrying attempt #{attempt + 1} after error: #{error_message}"

    if logger
      logger.info(message)
    else
      puts "INFO: #{message}"
    end
  end
end

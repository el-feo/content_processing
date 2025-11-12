# frozen_string_literal: true

# CredentialSanitizer provides utilities to sanitize AWS credentials for logging.
# This prevents accidental exposure of sensitive information in logs while still
# providing useful debugging information.
module CredentialSanitizer
  # Sanitizes AWS STS credentials for safe logging.
  # Shows first and last 4 characters of access key and session token,
  # completely redacts secret access key.
  #
  # @param credentials [Hash, nil] Hash containing accessKeyId, secretAccessKey, sessionToken
  # @return [Hash, nil] Sanitized credentials hash safe for logging
  def self.sanitize(credentials)
    return nil if credentials.nil?
    return '***INVALID_FORMAT***' unless credentials.is_a?(Hash)

    {
      'accessKeyId' => mask_credential(credentials['accessKeyId']),
      'secretAccessKey' => '***REDACTED***',
      'sessionToken' => mask_credential(credentials['sessionToken'])
    }
  end

  # Masks a credential by showing only first and last 4 characters.
  # For credentials shorter than 12 characters, completely redacts.
  #
  # @param value [String, nil] The credential value to mask
  # @return [String] Masked credential string
  def self.mask_credential(value)
    return '***MISSING***' if value.nil?
    return '***EMPTY***' if value.empty?
    return '***REDACTED***' if value.length < 12

    "#{value[0..3]}...#{value[-4..]}"
  end

  private_class_method :mask_credential
end

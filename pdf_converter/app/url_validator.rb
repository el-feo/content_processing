# frozen_string_literal: true

require 'uri'
require_relative '../lib/s3_url_parser'

# UrlValidator provides enhanced URL validation specifically for S3 signed URLs
# and general URL validation with additional S3-specific checks
class UrlValidator
  REQUIRED_S3_SIGNATURE_PARAMS = ['X-Amz-Algorithm'].freeze
  PDF_EXTENSIONS = ['.pdf'].freeze

  def initialize
    @logger = Logger.new($stdout) if defined?(Logger)
  end

  # Validates if a URL is a properly signed S3 URL for destination uploads
  # @param url [String] The URL to validate
  # @return [Boolean] true if URL is a valid signed S3 URL for uploads
  def valid_s3_destination_url?(url)
    validate_s3_url(url, require_pdf: false)
  end

  # Validates if a URL is a properly signed S3 URL for PDF files
  # @param url [String] The URL to validate
  # @return [Boolean] true if URL is a valid signed S3 URL for PDF
  def valid_s3_signed_url?(url)
    validate_s3_url(url, require_pdf: true)
  end

  # Basic URL validation for HTTP/HTTPS URLs
  # @param url [String] The URL to validate
  # @return [Boolean] true if URL is valid HTTP/HTTPS
  def valid_url?(url)
    return false if url.nil? || url.empty?

    begin
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      false
    end
  end

  # Extracts S3 bucket, key, and region information from S3 URL
  # @param url [String] The S3 URL to parse
  # @return [Hash, nil] Hash with :bucket, :key, :region or nil if invalid
  def extract_s3_info(url)
    return nil unless valid_s3_signed_url?(url)

    S3UrlParser.extract_s3_info(url)
  end

  private

  # Core validation logic shared by both destination and signed URL validation
  # @param url [String] The URL to validate
  # @param require_pdf [Boolean] Whether to check for PDF extension
  # @return [Boolean] true if URL passes all validation checks
  def validate_s3_url(url, require_pdf:)
    return false if url.nil? || url.empty?

    uri = URI.parse(url)

    # Validate scheme (HTTP only allowed for LocalStack)
    return false unless valid_scheme?(uri)

    # Must be S3 hostname or LocalStack
    return false unless valid_s3_host?(uri.host)

    # Check PDF extension if required
    return false if require_pdf && !pdf_file?(uri.path)

    # Must have required signature parameters
    s3_signature_params?(uri.query)
  rescue URI::InvalidURIError
    false
  end

  # Validates URL scheme (HTTPS required, except HTTP for LocalStack)
  # @param uri [URI] Parsed URI object
  # @return [Boolean] true if scheme is valid
  def valid_scheme?(uri)
    if uri.scheme == 'http'
      S3UrlParser.localstack_hostname?(uri.host)
    else
      uri.scheme == 'https'
    end
  end

  # Validates that hostname is either S3 or LocalStack
  # @param hostname [String] The hostname to validate
  # @return [Boolean] true if hostname is valid
  def valid_s3_host?(hostname)
    S3UrlParser.s3_hostname?(hostname) || S3UrlParser.localstack_hostname?(hostname)
  end

  def pdf_file?(path)
    return false if path.nil? || path.empty?

    # Extract filename from path
    filename = File.basename(path)
    PDF_EXTENSIONS.any? { |ext| filename.downcase.end_with?(ext) }
  end

  # Checks if query string contains required S3 signature parameters
  # @param query_string [String] The URL query string
  # @return [Boolean] true if all required signature params present
  def s3_signature_params?(query_string)
    return false if query_string.nil? || query_string.empty?

    query_params = URI.decode_www_form(query_string).to_h
    REQUIRED_S3_SIGNATURE_PARAMS.all? { |param| query_params.key?(param) }
  end

  def log_debug(message)
    @logger&.debug(message) if defined?(@logger)
  end
end

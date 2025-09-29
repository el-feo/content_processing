# frozen_string_literal: true

require 'uri'

# UrlValidator provides enhanced URL validation specifically for S3 signed URLs
# and general URL validation with additional S3-specific checks
class UrlValidator
  S3_HOSTNAME_PATTERNS = [
    /\As3\.amazonaws\.com\z/,                    # s3.amazonaws.com (US Standard)
    /\As3\.([a-z0-9-]+)\.amazonaws\.com\z/,     # s3.region.amazonaws.com
    /\A([a-z0-9.-]+)\.s3\.amazonaws\.com\z/,    # bucket.s3.amazonaws.com
    /\A([a-z0-9.-]+)\.s3\.([a-z0-9-]+)\.amazonaws\.com\z/ # bucket.s3.region.amazonaws.com
  ].freeze

  REQUIRED_S3_SIGNATURE_PARAMS = ['X-Amz-Algorithm'].freeze
  PDF_EXTENSIONS = ['.pdf'].freeze

  def initialize
    @logger = Logger.new($stdout) if defined?(Logger)
  end

  # Validates if a URL is a properly signed S3 URL for destination uploads
  # @param url [String] The URL to validate
  # @return [Boolean] true if URL is a valid signed S3 URL for uploads
  def valid_s3_destination_url?(url)
    return false if url.nil? || url.empty?

    begin
      uri = URI.parse(url)

      # Must be HTTPS
      return false unless uri.scheme == 'https'

      # Must be S3 hostname
      return false unless s3_hostname?(uri.host)

      # Must have signature parameters
      return false unless has_s3_signature_params?(uri.query)

      true
    rescue URI::InvalidURIError
      false
    end
  end

  # Validates if a URL is a properly signed S3 URL for PDF files
  # @param url [String] The URL to validate
  # @return [Boolean] true if URL is a valid signed S3 URL for PDF
  def valid_s3_signed_url?(url)
    return false if url.nil? || url.empty?

    begin
      uri = URI.parse(url)

      # Must be HTTPS
      return false unless uri.scheme == 'https'

      # Must be S3 hostname
      return false unless s3_hostname?(uri.host)

      # Must have PDF extension
      return false unless pdf_file?(uri.path)

      # Must have required signature parameters
      return false unless has_s3_signature_params?(uri.query)

      true
    rescue URI::InvalidURIError
      false
    end
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

    begin
      uri = URI.parse(url)

      if path_style_s3?(uri.host)
        extract_path_style_info(uri)
      elsif virtual_hosted_style_s3?(uri.host)
        extract_virtual_hosted_info(uri)
      else
        nil
      end
    rescue URI::InvalidURIError, StandardError
      nil
    end
  end

  private

  def s3_hostname?(hostname)
    return false if hostname.nil?

    S3_HOSTNAME_PATTERNS.any? { |pattern| hostname.match?(pattern) }
  end

  def pdf_file?(path)
    return false if path.nil? || path.empty?

    # Extract filename from path
    filename = File.basename(path)
    PDF_EXTENSIONS.any? { |ext| filename.downcase.end_with?(ext) }
  end

  def has_s3_signature_params?(query_string)
    return false if query_string.nil? || query_string.empty?

    query_params = URI.decode_www_form(query_string).to_h
    REQUIRED_S3_SIGNATURE_PARAMS.all? { |param| query_params.key?(param) }
  end

  def path_style_s3?(hostname)
    hostname&.match?(/\As3\./) || hostname == 's3.amazonaws.com'
  end

  def virtual_hosted_style_s3?(hostname)
    hostname&.match?(/\.s3\./)
  end

  def extract_path_style_info(uri)
    # For path-style: https://s3.region.amazonaws.com/bucket/key
    path_parts = uri.path.split('/', 3)
    return nil if path_parts.length < 3 || path_parts[1].empty?

    bucket = path_parts[1]
    key = path_parts[2]
    region = extract_region_from_hostname(uri.host) || 'us-east-1'

    {
      bucket: bucket,
      key: key,
      region: region
    }
  end

  def extract_virtual_hosted_info(uri)
    # For virtual-hosted-style: https://bucket.s3.region.amazonaws.com/key
    hostname_parts = uri.host.split('.')
    return nil if hostname_parts.length < 4

    bucket = hostname_parts[0]
    key = uri.path.start_with?('/') ? uri.path[1..-1] : uri.path
    region = extract_region_from_hostname(uri.host) || 'us-east-1'

    {
      bucket: bucket,
      key: key,
      region: region
    }
  end

  def extract_region_from_hostname(hostname)
    # Extract region from hostnames like s3.us-west-2.amazonaws.com
    if hostname.match(/s3\.([a-z0-9-]+)\.amazonaws\.com/)
      $1
    elsif hostname.match(/\.s3\.([a-z0-9-]+)\.amazonaws\.com/)
      $1
    else
      nil
    end
  end

  def log_debug(message)
    @logger&.debug(message) if defined?(@logger)
  end
end
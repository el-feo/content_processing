# frozen_string_literal: true

require 'uri'

# S3UrlParser handles parsing and extraction of information from S3 URLs
# supporting both path-style and virtual-hosted-style S3 URLs
class S3UrlParser
  S3_HOSTNAME_PATTERNS = [
    /\As3\.amazonaws\.com\z/, # s3.amazonaws.com (US Standard)
    /\As3\.([a-z0-9-]+)\.amazonaws\.com\z/,     # s3.region.amazonaws.com
    /\A([a-z0-9.-]+)\.s3\.amazonaws\.com\z/,    # bucket.s3.amazonaws.com
    /\A([a-z0-9.-]+)\.s3\.([a-z0-9-]+)\.amazonaws\.com\z/ # bucket.s3.region.amazonaws.com
  ].freeze

  # Checks if hostname matches S3 patterns
  # @param hostname [String] The hostname to check
  # @return [Boolean] true if hostname matches S3 patterns
  def self.s3_hostname?(hostname)
    return false if hostname.nil?

    S3_HOSTNAME_PATTERNS.any? { |pattern| hostname.match?(pattern) }
  end

  # Checks if hostname is LocalStack (for local testing)
  # @param hostname [String] The hostname to check
  # @return [Boolean] true if hostname is LocalStack
  def self.localstack_hostname?(hostname)
    return false if hostname.nil?

    # Allow localhost and 127.0.0.1 for LocalStack testing
    hostname == 'localhost' || hostname == '127.0.0.1' || hostname.start_with?('localstack')
  end

  # Checks if URL uses path-style S3 format
  # @param hostname [String] The hostname to check
  # @return [Boolean] true if path-style S3
  def self.path_style_s3?(hostname)
    hostname&.match?(/\As3\./) || hostname == 's3.amazonaws.com'
  end

  # Checks if URL uses virtual-hosted-style S3 format
  # @param hostname [String] The hostname to check
  # @return [Boolean] true if virtual-hosted-style S3
  def self.virtual_hosted_style_s3?(hostname)
    return false if hostname.nil?

    hostname.match?(/\.s3\./)
  end

  # Extracts S3 bucket, key, and region information from S3 URL
  # @param url [String] The S3 URL to parse
  # @return [Hash, nil] Hash with :bucket, :key, :region or nil if invalid
  def self.extract_s3_info(url)
    return nil if url.nil? || url.empty?

    uri = URI.parse(url)

    if path_style_s3?(uri.host)
      extract_path_style_info(uri)
    elsif virtual_hosted_style_s3?(uri.host)
      extract_virtual_hosted_info(uri)
    end
  rescue URI::InvalidURIError, StandardError
    nil
  end

  # Extracts region from S3 hostname
  # @param hostname [String] The S3 hostname
  # @return [String, nil] The region or nil if not found
  def self.extract_region_from_hostname(hostname)
    # Extract region from hostnames like s3.us-west-2.amazonaws.com
    match = hostname.match(/s3\.([a-z0-9-]+)\.amazonaws\.com/) ||
            hostname.match(/\.s3\.([a-z0-9-]+)\.amazonaws\.com/)
    match ? match[1] : nil
  end

  # Extracts info from path-style S3 URL
  # @param uri [URI] Parsed URI object
  # @return [Hash, nil] Hash with :bucket, :key, :region or nil
  def self.extract_path_style_info(uri)
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
  private_class_method :extract_path_style_info

  # Extracts info from virtual-hosted-style S3 URL
  # @param uri [URI] Parsed URI object
  # @return [Hash, nil] Hash with :bucket, :key, :region or nil
  def self.extract_virtual_hosted_info(uri)
    # For virtual-hosted-style: https://bucket.s3.region.amazonaws.com/key
    hostname_parts = uri.host.split('.')
    return nil if hostname_parts.length < 4

    bucket = hostname_parts[0]
    key = uri.path.start_with?('/') ? uri.path[1..] : uri.path
    region = extract_region_from_hostname(uri.host) || 'us-east-1'

    {
      bucket: bucket,
      key: key,
      region: region
    }
  end
  private_class_method :extract_virtual_hosted_info
end

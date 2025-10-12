# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'timeout'

# PdfDownloader handles downloading PDF files from S3 signed URLs
# with proper error handling and content validation
class PdfDownloader
  TIMEOUT_SECONDS = 30
  MAX_REDIRECTS = 5
  MAX_RETRY_ATTEMPTS = 3
  RETRY_DELAY_BASE = 1 # seconds
  VALID_PDF_MAGIC_NUMBERS = ['%PDF-1.', '%PDF-2.'].freeze

  # HTTP status codes that should trigger retries
  RETRYABLE_HTTP_CODES = [500, 502, 503, 504].freeze

  def initialize
    @logger = Logger.new($stdout) if defined?(Logger)
  end

  # Downloads a PDF from the given signed S3 URL with retry logic
  # @param url [String] The signed S3 URL to download from
  # @return [Hash] Result hash with :success, :content, :content_type, or :error
  def download(url)
    validate_url(url)

    log_info("Starting PDF download from: #{sanitize_url(url)}")

    uri = URI.parse(url)
    content, content_type = download_with_retry(uri)

    return error_result('Invalid PDF content: Does not contain valid PDF header') unless validate_pdf_content(content)

    log_info("PDF download completed successfully, size: #{content.bytesize} bytes")

    {
      success: true,
      content: content,
      content_type: content_type
    }
  rescue URI::InvalidURIError
    error_result('Invalid URL format')
  rescue StandardError => e
    error_result("Download failed: #{e.message}")
  end

  # Validates that the content is a valid PDF
  # @param content [String] The content to validate
  # @return [Boolean] true if content appears to be a valid PDF
  def validate_pdf_content(content)
    return false if content.nil? || content.empty?

    # Check for PDF magic number at the beginning
    VALID_PDF_MAGIC_NUMBERS.any? { |magic| content.start_with?(magic) }
  end

  private

  # Downloads content with retry logic for transient failures
  # @param uri [URI] The URI to download from
  # @return [Array] Array containing [content, content_type]
  def download_with_retry(uri)
    attempt = 1
    last_error = nil

    while attempt <= MAX_RETRY_ATTEMPTS
      begin
        return fetch_with_redirects(uri)
      rescue Timeout::Error => e
        last_error = "Download timeout after #{TIMEOUT_SECONDS} seconds"
        raise StandardError, "#{last_error} after #{attempt} attempts" unless should_retry?(attempt, e)

        log_retry(attempt, last_error)
        wait_before_retry(attempt)
        attempt += 1
        next
      rescue Errno::ECONNREFUSED => e
        last_error = "Connection refused: #{e.message}"
        raise StandardError, "#{last_error} after #{attempt} attempts" unless should_retry?(attempt, e)

        log_retry(attempt, last_error)
        wait_before_retry(attempt)
        attempt += 1
        next
      rescue SocketError => e
        last_error = "DNS resolution failed: #{e.message}"
        raise StandardError, "#{last_error} after #{attempt} attempts" unless should_retry?(attempt, e)

        log_retry(attempt, last_error)
        wait_before_retry(attempt)
        attempt += 1
        next
      rescue OpenSSL::SSL::SSLError => e
        last_error = "SSL connection failed: #{e.message}"
        raise StandardError, "#{last_error} after #{attempt} attempts" unless should_retry?(attempt, e)

        log_retry(attempt, last_error)
        wait_before_retry(attempt)
        attempt += 1
        next
      rescue NoMemoryError => e
        # Don't retry memory errors
        raise StandardError, "Memory exhaustion during download: #{e.message}"
      rescue StandardError => e
        # Check if it's a retryable HTTP error
        raise e unless e.message.match(/HTTP (\d+):/) && RETRYABLE_HTTP_CODES.include?(::Regexp.last_match(1).to_i)

        last_error = e.message
        raise StandardError, "#{last_error} after #{attempt} attempts" unless should_retry?(attempt, e)

        log_retry(attempt, last_error)
        wait_before_retry(attempt)
        attempt += 1
        next

        # Non-retryable error, re-raise immediately
      end
    end

    raise StandardError, "#{last_error} after #{MAX_RETRY_ATTEMPTS} attempts"
  end

  def should_retry?(attempt, _error)
    attempt < MAX_RETRY_ATTEMPTS
  end

  def log_retry(attempt, error_message)
    log_info("Retrying download attempt #{attempt + 1} after error: #{error_message}")
  end

  def wait_before_retry(attempt)
    delay = RETRY_DELAY_BASE * (2**(attempt - 1)) # Exponential backoff
    sleep(delay)
  end

  def validate_url(url)
    raise ArgumentError, 'URL cannot be nil or empty' if url.nil? || url.empty?

    uri = URI.parse(url)
    return if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    raise URI::InvalidURIError, 'URL must be HTTP or HTTPS'
  end

  def fetch_with_redirects(uri, redirect_count = 0)
    raise StandardError, "Too many redirects (max #{MAX_REDIRECTS})" if redirect_count >= MAX_REDIRECTS

    response = perform_http_request(uri)

    case response
    when Net::HTTPSuccess
      content_type = response['content-type'] || 'application/octet-stream'
      [response.body, content_type]
    when Net::HTTPRedirection
      location = response['location']
      raise StandardError, 'Redirect without location header' unless location

      log_info("Following redirect to: #{sanitize_url(location)}")
      new_uri = URI.parse(location)
      fetch_with_redirects(new_uri, redirect_count + 1)
    else
      raise StandardError, "HTTP #{response.code}: #{response.message}"
    end
  end

  def perform_http_request(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.read_timeout = TIMEOUT_SECONDS
      http.open_timeout = TIMEOUT_SECONDS

      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = 'PDF-Converter-Service/1.0'

      http.request(request)
    end
  end

  def error_result(message)
    log_error(message)
    {
      success: false,
      error: message
    }
  end

  def log_info(message)
    @logger&.info(message) || puts("INFO: #{message}")
  end

  def log_error(message)
    @logger&.error(message) || puts("ERROR: #{message}")
  end

  # Sanitizes URL for logging by removing query parameters that might contain secrets
  def sanitize_url(url)
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}#{uri.path}[QUERY_PARAMS_HIDDEN]"
  rescue StandardError
    '[URL_PARSE_ERROR]'
  end
end

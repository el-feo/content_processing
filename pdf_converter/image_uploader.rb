# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'timeout'
require 'async'
require 'async/barrier'
require 'async/semaphore'

# ImageUploader handles uploading images to S3 using pre-signed URLs
# with proper error handling, retries, and concurrent upload support
class ImageUploader
  TIMEOUT_SECONDS = 60 # Longer timeout for uploads
  MAX_RETRY_ATTEMPTS = 3
  RETRY_DELAY_BASE = 1 # seconds
  THREAD_POOL_SIZE = 5

  # HTTP status codes that should trigger retries
  RETRYABLE_HTTP_CODES = [500, 502, 503, 504].freeze

  def initialize
    @logger = Logger.new($stdout) if defined?(Logger)
  end

  # Uploads a single image to S3 using a pre-signed URL
  # @param url [String] The pre-signed S3 URL with PUT permissions
  # @param content [String] The image content to upload
  # @param content_type [String] The content type (e.g., 'image/png')
  # @return [Hash] Result hash with :success, :etag, or :error
  def upload(url, content, content_type = 'image/png')
    validate_inputs(url, content)

    log_info("Starting image upload to: #{sanitize_url(url)}")

    uri = URI.parse(url)
    etag = upload_with_retry(uri, content, content_type)

    log_info("Image upload completed successfully, ETag: #{etag}")

    {
      success: true,
      etag: etag,
      size: content.bytesize
    }
  rescue ArgumentError => e
    error_result(e.message)
  rescue URI::InvalidURIError
    error_result('Invalid URL format')
  rescue StandardError => e
    error_result("Upload failed: #{e.message}")
  end

  # Uploads multiple images concurrently to S3 using pre-signed URLs
  # @param urls [Array<String>] Array of pre-signed S3 URLs
  # @param images [Array<String>] Array of image contents to upload
  # @param content_type [String] The content type for all images
  # @return [Array<Hash>] Array of result hashes for each upload
  def upload_batch(urls, images, content_type = 'image/png')
    unless urls.size == images.size
      raise ArgumentError, 'Number of URLs must match number of images'
    end

    log_info("Starting batch upload of #{urls.size} images")
    results = []

    Async do
      barrier = Async::Barrier.new
      semaphore = Async::Semaphore.new(THREAD_POOL_SIZE, parent: barrier)

      urls.zip(images).each_with_index do |(url, content), index|
        semaphore.async do
          result = upload(url, content, content_type)
          result[:index] = index
          results << result
        end
      end

      # Wait for all uploads to complete
      barrier.wait
    end

    # Sort results by index to maintain order
    results.sort_by! { |r| r[:index] }

    successful = results.count { |r| r[:success] }
    log_info("Batch upload completed: #{successful}/#{results.size} successful")

    results
  end

  private

  def validate_inputs(url, content)
    raise ArgumentError, 'URL cannot be nil or empty' if url.nil? || url.empty?
    raise ArgumentError, 'Content cannot be nil or empty' if content.nil? || content.empty?
  end

  # Uploads content with retry logic for transient failures
  # @param uri [URI] The URI to upload to
  # @param content [String] The content to upload
  # @param content_type [String] The content type
  # @return [String] The ETag from the successful upload
  def upload_with_retry(uri, content, content_type)
    attempt = 1
    last_error = nil

    while attempt <= MAX_RETRY_ATTEMPTS
      begin
        return perform_upload(uri, content, content_type)
      rescue Timeout::Error => e
        last_error = "Upload timeout after #{TIMEOUT_SECONDS} seconds"
        handle_retry(attempt, last_error)
        attempt += 1
      rescue StandardError => e
        # Check for specific HTTP errors
        if e.message.include?('403')
          raise StandardError, 'Access denied - URL may be expired or invalid'
        elsif e.message.match(/HTTP (4\d\d):/)
          # Don't retry client errors (4xx)
          raise StandardError, "Client error: #{e.message}"
        elsif retryable_error?(e)
          last_error = e.message
          handle_retry(attempt, last_error)
          attempt += 1
        else
          # Non-retryable error, re-raise immediately
          raise e
        end
      end
    end

    raise StandardError, "#{last_error} after #{MAX_RETRY_ATTEMPTS} attempts"
  end

  def handle_retry(attempt, error_message)
    if attempt < MAX_RETRY_ATTEMPTS
      log_info("Retrying upload attempt #{attempt + 1} after error: #{error_message}")
      wait_before_retry(attempt)
    end
  end

  def retryable_error?(error)
    return true if error.is_a?(Errno::ECONNREFUSED)
    return true if error.is_a?(SocketError)
    return true if error.is_a?(OpenSSL::SSL::SSLError)

    if error.message.match(/HTTP (\d+):/)
      RETRYABLE_HTTP_CODES.include?($1.to_i)
    else
      false
    end
  end

  def wait_before_retry(attempt)
    delay = RETRY_DELAY_BASE * (2 ** (attempt - 1)) # Exponential backoff
    sleep(delay)
  end

  def perform_upload(uri, content, content_type)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.read_timeout = TIMEOUT_SECONDS
      http.open_timeout = TIMEOUT_SECONDS

      request = Net::HTTP::Put.new(uri)
      request['Content-Type'] = content_type
      request['Content-Length'] = content.bytesize.to_s
      request.body = content

      http.request(request)
    end

    case response
    when Net::HTTPSuccess
      response['ETag'] || response['etag'] || 'no-etag'
    when Net::HTTPRedirection
      raise StandardError, 'Unexpected redirect during upload'
    else
      raise StandardError, "HTTP #{response.code}: #{response.message}"
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
  rescue
    '[URL_PARSE_ERROR]'
  end
end
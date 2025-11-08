# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'timeout'
require 'async'
require 'async/barrier'
require 'async/semaphore'
require_relative '../lib/retry_handler'
require_relative '../lib/url_utils'

# ImageUploader handles uploading images to S3 using pre-signed URLs
# with proper error handling, retries, and concurrent upload support
class ImageUploader
  include UrlUtils

  TIMEOUT_SECONDS = 60 # Longer timeout for uploads
  THREAD_POOL_SIZE = 5

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
    # Provide better error message for 403 errors
    if e.message.include?('403')
      error_result('Access denied - URL may be expired or invalid')
    else
      error_result("Upload failed: #{e.message}")
    end
  end

  # Uploads multiple images concurrently to S3 using pre-signed URLs
  # @param urls [Array<String>] Array of pre-signed S3 URLs
  # @param images [Array<String>] Array of image contents to upload
  # @param content_type [String] The content type for all images
  # @return [Array<Hash>] Array of result hashes for each upload
  def upload_batch(urls, images, content_type = 'image/png')
    raise ArgumentError, 'Number of URLs must match number of images' unless urls.size == images.size

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

  # Uploads image files to S3 destination using pre-signed URL
  # @param destination_url [String] Pre-signed S3 destination URL
  # @param image_paths [Array<String>] Array of image file paths
  # @return [Hash] Result with :success, :uploaded_urls, :etags, or :error
  def upload_images_from_files(destination_url, image_paths)
    base_uri = parse_destination_url(destination_url)
    image_urls, image_contents = prepare_images_for_upload(image_paths, base_uri)

    upload_results = upload_batch(image_urls, image_contents, 'image/png')
    process_upload_results(upload_results, image_urls)
  rescue StandardError => e
    {
      success: false,
      error: "Upload error: #{e.message}"
    }
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
    RetryHandler.with_retry(logger: @logger) do
      perform_upload(uri, content, content_type)
    end
  rescue RetryHandler::RetryError => e
    raise StandardError, e.message
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

  # Parses the destination URL and returns a base URI with proper path.
  #
  # @param destination_url [String] Destination URL
  # @return [URI] Base URI with normalized path
  def parse_destination_url(destination_url)
    uri = URI.parse(destination_url)
    uri_path = uri.path
    uri.path = uri_path.end_with?('/') ? uri_path : "#{uri_path}/"
    uri
  end

  # Prepares image URLs and contents for batch upload.
  #
  # @param image_paths [Array<String>] Image file paths
  # @param base_uri [URI] Base URI for uploads
  # @return [Array<Array>] Two arrays: URLs and contents
  def prepare_images_for_upload(image_paths, base_uri)
    image_urls = []
    image_contents = []

    image_paths.each_with_index do |image_path, index|
      image_uri = base_uri.dup
      image_uri.path = "#{base_uri.path}page-#{index + 1}.png"

      image_urls << image_uri.to_s
      image_contents << File.read(image_path, mode: 'rb')
    end

    [image_urls, image_contents]
  end

  # Processes upload results and returns success or failure hash.
  #
  # @param upload_results [Array<Hash>] Upload results
  # @param image_urls [Array<String>] Image URLs
  # @return [Hash] Result with :success, :uploaded_urls, :etags, or :error
  def process_upload_results(upload_results, image_urls)
    failed_uploads = upload_results.reject { |result| result[:success] }

    if failed_uploads.any?
      error_messages = failed_uploads.map { |result| result[:error] }.uniq.join(', ')
      return {
        success: false,
        error: "Failed to upload #{failed_uploads.size} images: #{error_messages}"
      }
    end

    {
      success: true,
      uploaded_urls: UrlUtils.strip_query_params(image_urls),
      etags: upload_results.map { |result| result[:etag] }
    }
  end
end

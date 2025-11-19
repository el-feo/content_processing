# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'timeout'
require 'async'
require 'async/barrier'
require 'async/semaphore'
require_relative '../lib/retry_handler'
require_relative '../lib/url_utils'
require_relative '../lib/zip_builder'

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
  rescue ArgumentError => error
    error_result(error.message)
  rescue URI::InvalidURIError
    error_result('Invalid URL format')
  rescue StandardError => error
    # Provide better error message for 403 errors
    error_message = error.message
    if error_message.include?('403')
      error_result('Access denied - URL may be expired or invalid')
    else
      error_result("Upload failed: #{error_message}")
    end
  end

  # Uploads multiple images concurrently to S3 using pre-signed URLs
  # @param urls [Array<String>] Array of pre-signed S3 URLs
  # @param images [Array<String>] Array of image contents to upload
  # @param content_type [String] The content type for all images
  # @return [Array<Hash>] Array of result hashes for each upload
  def upload_batch(urls, images, content_type = 'image/png')
    validate_batch_inputs(urls, images)
    log_info("Starting batch upload of #{urls.size} images")

    results = perform_concurrent_uploads(urls, images, content_type)
    log_batch_completion(results)

    results
  end

  # Uploads image files to S3 destination as a zip file using pre-signed URL
  # @param destination_url [String] Pre-signed S3 destination URL for the zip file
  # @param image_paths [Array<String>] Array of image file paths
  # @param unique_id [String] Unique identifier for naming images in the zip
  # @return [Hash] Result with :success, :zip_url, :etag, or :error
  def upload_images_from_files(destination_url, image_paths, unique_id)
    log_info("Creating zip file with #{image_paths.size} images")

    # Create zip file in memory
    zip_content = ZipBuilder.create_from_images(image_paths, unique_id)

    log_info("Zip file created, size: #{zip_content.bytesize} bytes")

    # Upload zip file to S3
    upload_result = upload(destination_url, zip_content, 'application/zip')

    return { success: false, error: upload_result[:error] } unless upload_result[:success]

    {
      success: true,
      zip_url: UrlUtils.strip_query_params([destination_url]).first,
      etag: upload_result[:etag]
    }
  rescue StandardError => error
    {
      success: false,
      error: "Zip upload error: #{error.message}"
    }
  end

  private

  def validate_inputs(url, content)
    raise ArgumentError, 'URL cannot be nil or empty' if url.nil? || url.empty?
    raise ArgumentError, 'Content cannot be nil or empty' if content.nil? || content.empty?
  end

  def validate_batch_inputs(urls, images)
    raise ArgumentError, 'Number of URLs must match number of images' unless urls.size == images.size
  end

  def perform_concurrent_uploads(urls, images, content_type)
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

      barrier.wait
    end

    results.sort_by! { |result| result[:index] }
    results
  end

  def log_batch_completion(results)
    successful = results.count { |result| result[:success] }
    log_info("Batch upload completed: #{successful}/#{results.size} successful")
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
  rescue RetryHandler::RetryError => error
    raise StandardError, error.message
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
end

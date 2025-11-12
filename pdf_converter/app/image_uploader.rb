# frozen_string_literal: true

require 'aws-sdk-s3'
require_relative '../lib/credential_sanitizer'

# ImageUploader handles uploading converted images to S3 using temporary credentials.
# It supports both credential-based access (for clients) and IAM role-based access
# (for Lambda's default execution role).
class ImageUploader
  def initialize(credentials = nil)
    @credentials = credentials
  end

  # Uploads image files to S3 destination bucket/prefix using credentials.
  # Generates keys in the format: {prefix}/{unique_id}-{page_number}.png
  #
  # @param bucket [String] S3 destination bucket name
  # @param prefix [String] S3 object prefix (folder path)
  # @param unique_id [String] Unique identifier for this conversion
  # @param image_paths [Array<String>] Array of image file paths to upload
  # @return [Hash] Result with :success, :uploaded_keys, :etags, or :error
  def upload_images_to_s3(bucket, prefix, unique_id, image_paths)
    log_upload_start(bucket, prefix, image_paths.size)

    s3_client = create_s3_client
    uploaded_keys = []
    etags = []

    image_paths.each_with_index do |image_path, index|
      key = build_s3_key(prefix, unique_id, index)

      result = upload_single_image(s3_client, bucket, key, image_path)
      return result unless result[:success]

      uploaded_keys << key
      etags << result[:etag]
    end

    log_upload_success(uploaded_keys.size)

    {
      success: true,
      uploaded_keys: uploaded_keys,
      etags: etags
    }
  rescue Aws::S3::Errors::AccessDenied
    error_result('Access denied to destination bucket - check credentials permissions')
  rescue Aws::Errors::ServiceError => e
    error_result("S3 error: #{e.message}")
  rescue StandardError => e
    error_result("Upload failed: #{e.message}")
  end

  private

  # Uploads a single image to S3.
  #
  # @param s3_client [Aws::S3::Client] S3 client instance
  # @param bucket [String] S3 bucket name
  # @param key [String] S3 object key
  # @param image_path [String] Path to image file
  # @return [Hash] Result with :success, :etag, or :error
  def upload_single_image(s3_client, bucket, key, image_path)
    File.open(image_path, 'rb') do |file|
      response = s3_client.put_object(
        bucket: bucket,
        key: key,
        body: file,
        content_type: 'image/png'
      )

      puts "Uploaded image: s3://#{bucket}/#{key}, ETag: #{response.etag}"

      {
        success: true,
        etag: response.etag
      }
    end
  rescue Aws::S3::Errors::ServiceError => e
    error_result("Failed to upload #{key}: #{e.message}")
  end

  # Builds S3 key from prefix, unique_id, and page number.
  # Format: prefix/unique_id-page_number.png
  # Example: output/test-123-0.png
  #
  # @param prefix [String] S3 prefix (may be empty)
  # @param unique_id [String] Unique identifier
  # @param page_number [Integer] Zero-based page number
  # @return [String] S3 object key
  def build_s3_key(prefix, unique_id, page_number)
    prefix = prefix.to_s.strip
    prefix = prefix.end_with?('/') ? prefix : "#{prefix}/"
    prefix = '' if prefix == '/'

    "#{prefix}#{unique_id}-#{page_number}.png"
  end

  # Creates an S3 client using the provided credentials or default IAM role.
  #
  # @return [Aws::S3::Client] Configured S3 client
  def create_s3_client
    if @credentials
      Aws::S3::Client.new(
        access_key_id: @credentials['accessKeyId'],
        secret_access_key: @credentials['secretAccessKey'],
        session_token: @credentials['sessionToken']
      )
    else
      # Use Lambda's IAM role
      Aws::S3::Client.new
    end
  end

  def log_upload_start(bucket, prefix, count)
    if @credentials
      sanitized = CredentialSanitizer.sanitize(@credentials)
      puts "Uploading #{count} images to s3://#{bucket}/#{prefix} using credentials: #{sanitized['accessKeyId']}"
    else
      puts "Uploading #{count} images to s3://#{bucket}/#{prefix} using Lambda IAM role"
    end
  end

  def log_upload_success(count)
    puts "Successfully uploaded #{count} images to S3"
  end

  def error_result(message)
    puts "ERROR: #{message}"
    {
      success: false,
      error: message
    }
  end
end

# frozen_string_literal: true

require 'aws-sdk-s3'
require_relative '../lib/credential_sanitizer'

# PdfDownloader handles downloading PDF files from S3 using temporary credentials.
# It supports both credential-based access (for clients) and IAM role-based access
# (for Lambda's default execution role).
class PdfDownloader
  # Maximum PDF file size (100MB)
  MAX_PDF_SIZE = 100 * 1024 * 1024
  VALID_PDF_MAGIC_NUMBERS = ['%PDF-1.', '%PDF-2.'].freeze

  def initialize(credentials = nil)
    @credentials = credentials
  end

  # Downloads a PDF file from S3 using the provided bucket and key.
  # Performs a preflight check to verify access and validate the file.
  #
  # @param bucket [String] S3 bucket name
  # @param key [String] S3 object key
  # @return [Hash] Result hash with :success, :content, :metadata, or :error
  def download_from_s3(bucket, key)
    log_download_start(bucket, key)

    # Preflight check: verify access and file properties
    preflight_result = preflight_check(bucket, key)
    return preflight_result unless preflight_result[:success]

    # Download the PDF content
    s3_client = create_s3_client
    response = s3_client.get_object(bucket: bucket, key: key)

    content = response.body.read

    # Validate PDF content
    unless validate_pdf_content(content)
      return error_result('Invalid PDF content: Does not contain valid PDF header')
    end

    log_download_success(content.bytesize)

    {
      success: true,
      content: content,
      metadata: {
        content_type: response.content_type,
        content_length: response.content_length,
        etag: response.etag
      }
    }
  rescue Aws::S3::Errors::NoSuchKey
    error_result('Source PDF not found')
  rescue Aws::S3::Errors::AccessDenied
    error_result('Access denied to source PDF - check credentials permissions')
  rescue Aws::Errors::ServiceError => e
    error_result("S3 error: #{e.message}")
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

  # Performs a preflight check on the S3 object to verify:
  # 1. Object exists and credentials have access
  # 2. File size is within limits
  # 3. Content type is PDF (if metadata available)
  #
  # @param bucket [String] S3 bucket name
  # @param key [String] S3 object key
  # @return [Hash] Result hash with :success or :error
  def preflight_check(bucket, key)
    s3_client = create_s3_client

    # Use head_object to check without downloading
    response = s3_client.head_object(bucket: bucket, key: key)

    # Validate file size
    if response.content_length > MAX_PDF_SIZE
      return error_result("PDF file too large: #{response.content_length} bytes (max: #{MAX_PDF_SIZE})")
    end

    # Validate content type if available
    if response.content_type && !response.content_type.include?('pdf')
      puts "WARNING: Content-Type is #{response.content_type}, expected PDF"
    end

    puts "Preflight check passed: #{response.content_length} bytes, Content-Type: #{response.content_type}"
    { success: true }
  rescue Aws::S3::Errors::NotFound
    error_result('Source PDF not found')
  rescue Aws::S3::Errors::AccessDenied
    error_result('Access denied during preflight check - verify credentials have s3:GetObject permission')
  rescue Aws::Errors::ServiceError => e
    error_result("Preflight check failed: #{e.message}")
  end

  # Creates an S3 client using the provided credentials or default IAM role
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

  def log_download_start(bucket, key)
    if @credentials
      sanitized = CredentialSanitizer.sanitize(@credentials)
      puts "Downloading PDF from s3://#{bucket}/#{key} using credentials: #{sanitized['accessKeyId']}"
    else
      puts "Downloading PDF from s3://#{bucket}/#{key} using Lambda IAM role"
    end
  end

  def log_download_success(size)
    puts "PDF downloaded successfully: #{size} bytes"
  end

  def error_result(message)
    puts "ERROR: #{message}"
    {
      success: false,
      error: message
    }
  end
end

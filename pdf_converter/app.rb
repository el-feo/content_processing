require 'json'
require 'httparty'
require 'jwt'
require 'logger'
require 'base64'
require 'net/http'
require 'uri'
require 'tempfile'
require 'fileutils'
require 'aws-sdk-secretsmanager'
require 'aws-sdk-cloudwatch'
require 'aws-sdk-s3'
require 'concurrent'

# Configuration
module Config
  MAX_PDF_SIZE = ENV['MAX_PDF_SIZE']&.to_i || 104_857_600  # 100MB default
  MAX_PAGES = ENV['MAX_PAGES']&.to_i || 100
  DPI = ENV['PDF_DPI']&.to_i || 150
  CONCURRENT_PAGES = ENV['CONCURRENT_PAGES']&.to_i || 5
  WEBHOOK_TIMEOUT = ENV['WEBHOOK_TIMEOUT']&.to_i || 10
  WEBHOOK_RETRIES = ENV['WEBHOOK_RETRIES']&.to_i || 3
  ALLOWED_MIME_TYPES = ['application/pdf', 'application/x-pdf']
end

# Set up libvips library path before requiring vips
ENV['LD_LIBRARY_PATH'] = "/usr/local/lib:/usr/local/lib64:#{ENV['LD_LIBRARY_PATH']}"
ENV['VIPS_LIBRARY_PATH'] = '/usr/local/lib'

# Load libvips with version check
begin
  require 'vips'

  # Verify libvips version
  vips_version = Vips.version_string
  unless vips_version
    raise LoadError, "Failed to detect libvips version"
  end

  # Log the version for debugging
  puts "Loaded libvips version: #{vips_version}"
rescue LoadError => e
  puts "Error loading libvips: #{e.message}"
  # Try alternative loading method
  ENV['RUBY_DL_LIBRARY_PATH'] = '/usr/local/lib'
  require 'vips'
end

class URLValidator
  ALLOWED_SCHEMES = ['https'].freeze
  S3_HOSTS_REGEX = /\.s3[.-].*\.amazonaws\.com$|\.s3\.amazonaws\.com$/i

  def self.validate_s3_url(url, is_localstack = false)
    uri = URI.parse(url)

    # Always allow s3:// scheme, and for LocalStack also allow http/https
    if uri.scheme&.downcase == 's3'
      # S3 URLs are always valid (bucket validation happens later)
      return { valid: true }
    elsif is_localstack && ['http', 'https'].include?(uri.scheme&.downcase)
      # In LocalStack mode, also allow HTTP/HTTPS for direct LocalStack endpoints
      return { valid: true }
    elsif ALLOWED_SCHEMES.include?(uri.scheme&.downcase)
      # For production, only allow HTTPS URLs to S3 hosts
      unless uri.host&.match?(S3_HOSTS_REGEX)
        return { valid: false, error: "URL must be an S3 URL" }
      end
    else
      scheme_message = is_localstack ? "Only s3://, HTTP, or HTTPS URLs are allowed" : "Only s3:// or HTTPS S3 URLs are allowed"
      return { valid: false, error: scheme_message }
    end

    # Check for path traversal attempts
    if uri.path&.include?('..') || uri.path&.include?('//')
      return { valid: false, error: "Invalid path in URL" }
    end

    { valid: true }
  rescue URI::InvalidURIError => e
    { valid: false, error: "Invalid URL format: #{e.message}" }
  end

  def self.validate_webhook_url(url, is_localstack = false)
    uri = URI.parse(url)

    # Allow HTTP for LocalStack testing
    allowed_schemes = is_localstack ? ['https', 'http'] : ALLOWED_SCHEMES
    unless allowed_schemes.include?(uri.scheme&.downcase)
      scheme_message = is_localstack ? "Only HTTP/HTTPS webhooks are allowed" : "Only HTTPS webhooks are allowed"
      return { valid: false, error: scheme_message }
    end

    # Prevent localhost/internal network calls for security (except in LocalStack)
    if !is_localstack && uri.host&.match?(/^(localhost|127\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)/)
      return { valid: false, error: "Webhook URL cannot point to internal network" }
    end

    { valid: true }
  rescue URI::InvalidURIError => e
    { valid: false, error: "Invalid webhook URL: #{e.message}" }
  end
end

class MetricsPublisher
  def initialize(logger, is_localstack = false)
    @logger = logger
    @is_localstack = is_localstack
    @cloudwatch = begin
      if @is_localstack
        # Use host.docker.internal for SAM local, otherwise use provided endpoint or localhost
        if ENV['AWS_SAM_LOCAL'] == 'true'
          endpoint = ENV['AWS_ENDPOINT_URL'] || 'http://host.docker.internal:4566'
        else
          endpoint = ENV['AWS_ENDPOINT_URL'] || 'http://localhost:4566'
        end
        Aws::CloudWatch::Client.new(
          region: ENV['AWS_REGION'] || 'us-east-1',
          endpoint: endpoint,
          access_key_id: 'test',
          secret_access_key: 'test'
        )
      else
        Aws::CloudWatch::Client.new(region: ENV['AWS_REGION'] || 'us-east-1')
      end
    rescue => e
      @logger.warn("CloudWatch client initialization failed: #{e.message}")
      nil
    end
  end

  def publish(metric_name, value, unit = 'Count', dimensions = [])
    return unless @cloudwatch

    @cloudwatch.put_metric_data(
      namespace: 'PDFProcessor',
      metric_data: [{
        metric_name: metric_name,
        value: value,
        unit: unit,
        timestamp: Time.now,
        dimensions: dimensions
      }]
    )
  rescue => e
    @logger.warn("Failed to publish metric #{metric_name}: #{e.message}")
  end
end

class PDFProcessor
  def initialize(event, context)
    @event = event
    @context = context
    @logger = context.respond_to?(:logger) ? context.logger : Logger.new(STDOUT)

    # Detect LocalStack environment
    @is_localstack = ENV['LOCALSTACK_HOSTNAME'] || ENV['AWS_ENDPOINT_URL']&.include?('localhost') || ENV['AWS_ENDPOINT_URL']&.include?('4566') || ENV['AWS_SAM_LOCAL'] == 'true'

    if @is_localstack
      configure_for_localstack
    end

    @metrics = MetricsPublisher.new(@logger, @is_localstack)
    @start_time = Time.now
  end

  def process
    begin
      # Parse request
      body = parse_request_body
      headers = @event['headers'] || @event[:headers] || {}

      # Authenticate
      unless authenticate_request(headers)
        @metrics.publish('AuthenticationFailures', 1)
        return error_response(401, 'Unauthorized')
      end

      # Validate payload
      validation_error = validate_payload(body)
      if validation_error
        @metrics.publish('ValidationErrors', 1)
        return validation_error
      end

      # Process PDF
      @logger.info("Starting PDF processing for source: #{body['source']}")
      @metrics.publish('ProcessingStarted', 1)

      # Download PDF from source URL with size check
      pdf_file = download_pdf_with_limits(body['source'])

      # Validate PDF MIME type
      unless validate_pdf_mime_type(pdf_file)
        cleanup_temp_files(pdf_file, [])
        @metrics.publish('InvalidPDFFormat', 1)
        return error_response(400, 'Invalid file format. Only PDF files are accepted.')
      end

      # Convert PDF to images with concurrent processing
      image_files = convert_pdf_to_images_concurrent(pdf_file)

      # Upload images to destination with retry logic
      uploaded_urls = upload_images_to_s3_with_retry(image_files, body['destination'])

      # Send webhook notification with retry
      if body['webhook']
        send_webhook_with_retry(body['webhook'], {
          status: 'success',
          source: body['source'],
          destination: body['destination'],
          images_count: uploaded_urls.length,
          image_urls: uploaded_urls
        })
      end

      # Clean up temp files
      cleanup_temp_files(pdf_file, image_files)

      # Publish success metrics
      processing_time = Time.now - @start_time
      @metrics.publish('ProcessingTime', processing_time, 'Seconds')
      @metrics.publish('ProcessingSuccess', 1)
      @metrics.publish('PagesProcessed', uploaded_urls.length)

      # Return success response
      {
        statusCode: 200,
        headers: {
          'Content-Type' => 'application/json',
          'X-Processing-Time' => processing_time.to_s
        },
        body: {
          status: 'success',
          message: 'PDF processed successfully',
          images_count: uploaded_urls.length,
          image_urls: uploaded_urls,
          processing_time_seconds: processing_time.round(2)
        }.to_json
      }

    rescue StandardError => e
      @logger.error("Error processing PDF: #{e.message}")
      @logger.error(e.backtrace.join("\n"))

      @metrics.publish('ProcessingErrors', 1)
      @metrics.publish('ProcessingTime', Time.now - @start_time, 'Seconds')

      # Attempt to send error webhook if available
      if body && body['webhook']
        begin
          send_webhook_with_retry(body['webhook'], {
            status: 'error',
            error: e.message,
            source: body['source'],
            timestamp: Time.now.iso8601
          }, max_retries: 1)
        rescue => webhook_error
          @logger.error("Failed to send error webhook: #{webhook_error.message}")
        end
      end

      error_response(500, "Processing error: #{e.message}")
    end
  end

  private

  def parse_request_body
    return {} unless @event['body'] || @event[:body]

    body = @event['body'] || @event[:body]
    # Handle base64 encoded body from API Gateway
    if @event['isBase64Encoded'] || @event[:isBase64Encoded]
      body = Base64.decode64(body)
    end

    JSON.parse(body)
  rescue JSON::ParserError => e
    raise "Invalid JSON in request body: #{e.message}"
  end

  def jwt_secret
    @jwt_secret ||= fetch_jwt_secret_from_secrets_manager
  end

  def fetch_jwt_secret_from_secrets_manager
    secret_name = ENV['JWT_SECRET_NAME'] || 'pdf-processor/jwt-secret'
    region = ENV['AWS_REGION'] || 'us-east-1'

    # For local testing, use environment variable if available
    @logger.info("AWS_SAM_LOCAL=#{ENV['AWS_SAM_LOCAL']}, LOCAL_TESTING=#{ENV['LOCAL_TESTING']}, JWT_SECRET env=#{ENV['JWT_SECRET']&.[](0..10)}")
    if ENV['LOCAL_TESTING'] == 'true' || ENV['AWS_SAM_LOCAL'] == 'true' || ENV['AWS_SAM_LOCAL']
      local_secret = ENV['JWT_SECRET'] || 'localstack-secret-key'  # Changed default to localstack-secret-key
      @logger.info("Running in local mode, using local JWT secret: #{local_secret[0..10]}...")
      return local_secret
    end

    client = Aws::SecretsManager::Client.new(region: region)

    begin
      response = client.get_secret_value(secret_id: secret_name)

      if response.secret_string
        secret_data = JSON.parse(response.secret_string)
        secret_data['jwt_secret'] || secret_data['secret'] || response.secret_string
      else
        Base64.decode64(response.secret_binary)
      end
    rescue Aws::SecretsManager::Errors::ResourceNotFoundException => e
      @logger.error("Secret #{secret_name} not found: #{e.message}")
      # Fall back to environment variable for local testing
      if ENV['JWT_SECRET']
        @logger.info("Using fallback JWT_SECRET from environment")
        return ENV['JWT_SECRET']
      end
      raise "JWT secret not found in AWS Secrets Manager"
    rescue => e
      @logger.error("Unexpected error retrieving secret: #{e.message}")
      # Fall back to environment variable for local testing
      if ENV['JWT_SECRET']
        @logger.info("Using fallback JWT_SECRET from environment due to error")
        return ENV['JWT_SECRET']
      end
      raise "Failed to retrieve JWT secret"
    end
  end

  def authenticate_request(headers)
    # Extract JWT from Authorization header
    auth_header = headers['Authorization'] || headers['authorization']
    return false unless auth_header

    token = auth_header.gsub(/^Bearer\s+/, '')

    begin
      decoded_token = JWT.decode(token, jwt_secret, true, algorithm: 'HS256')
      @logger.info("Authenticated request for user: #{decoded_token[0]['sub']}")
      true
    rescue JWT::ExpiredSignature => e
      @logger.error("JWT expired: #{e.message}")
      false
    rescue JWT::InvalidIatError => e
      @logger.error("JWT invalid issued at time: #{e.message}")
      false
    rescue JWT::VerificationError => e
      @logger.error("JWT verification failed: #{e.message}")
      false
    rescue => e
      @logger.error("JWT authentication failed: #{e.class} - #{e.message}")
      false
    end
  end

  def validate_payload(body)
    return error_response(400, 'Missing required field: source') unless body['source']
    return error_response(400, 'Missing required field: destination') unless body['destination']

    # Validate source URL
    source_validation = URLValidator.validate_s3_url(body['source'], @is_localstack)
    unless source_validation[:valid]
      return error_response(400, "Invalid source URL: #{source_validation[:error]}")
    end

    # Validate destination URL
    dest_validation = URLValidator.validate_s3_url(body['destination'], @is_localstack)
    unless dest_validation[:valid]
      return error_response(400, "Invalid destination URL: #{dest_validation[:error]}")
    end

    # Validate webhook URL if provided
    if body['webhook']
      webhook_validation = URLValidator.validate_webhook_url(body['webhook'], @is_localstack)
      unless webhook_validation[:valid]
        return error_response(400, "Invalid webhook URL: #{webhook_validation[:error]}")
      end
    end

    nil
  end

  def download_pdf_with_limits(source_url)
    @logger.info("Downloading PDF from: #{source_url}")

    # Convert LocalStack S3 URLs if needed
    actual_url = source_url
    if @is_localstack && source_url.start_with?('s3://')
      bucket, key = source_url.sub('s3://', '').split('/', 2)
      # Use host.docker.internal for SAM local, otherwise use provided endpoint or localhost
      if ENV['AWS_SAM_LOCAL'] == 'true'
        endpoint = ENV['AWS_ENDPOINT_URL'] || 'http://host.docker.internal:4566'
      else
        endpoint = ENV['AWS_ENDPOINT_URL'] || 'http://localhost:4566'
      end
      actual_url = "#{endpoint}/#{bucket}/#{key}"
      @logger.info("Converted S3 URL for LocalStack: #{actual_url}")
    end

    uri = URI(actual_url)

    # Use streaming to check size before fully downloading
    temp_pdf = Tempfile.new(['pdf_input', '.pdf'])
    temp_pdf.binmode

    downloaded_size = 0

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)

      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          raise "Failed to download PDF: HTTP #{response.code} - #{response.message}"
        end

        # Check Content-Length header if available
        if response['Content-Length']
          content_length = response['Content-Length'].to_i
          if content_length > Config::MAX_PDF_SIZE
            raise "PDF file too large: #{content_length} bytes (max: #{Config::MAX_PDF_SIZE} bytes)"
          end
        end

        # Stream the response body
        response.read_body do |chunk|
          downloaded_size += chunk.bytesize

          if downloaded_size > Config::MAX_PDF_SIZE
            temp_pdf.close!
            raise "PDF file too large: exceeds #{Config::MAX_PDF_SIZE} bytes limit"
          end

          temp_pdf.write(chunk)
        end
      end
    end

    temp_pdf.rewind
    @logger.info("PDF downloaded successfully, size: #{downloaded_size} bytes")
    temp_pdf
  end

  def validate_pdf_mime_type(pdf_file)
    # Check file header for PDF signature
    pdf_file.rewind
    header = pdf_file.read(5)
    pdf_file.rewind

    # PDF files should start with %PDF-
    header == '%PDF-'
  end

  def convert_pdf_to_images_concurrent(pdf_file)
    @logger.info("Converting PDF to images with concurrent processing")

    begin
      # Load PDF to get page count
      pdf = Vips::Image.new_from_file(pdf_file.path, access: :sequential)
      n_pages = pdf.get('n-pages')

      if n_pages > Config::MAX_PAGES
        raise "PDF has too many pages: #{n_pages} (max: #{Config::MAX_PAGES})"
      end

      @logger.info("PDF has #{n_pages} pages")

      # Process pages concurrently
      pool = Concurrent::FixedThreadPool.new(Config::CONCURRENT_PAGES)
      image_files = Concurrent::Array.new
      errors = Concurrent::Array.new

      promises = (0...n_pages).map do |page_num|
        Concurrent::Promise.execute(executor: pool) do
          begin
            @logger.info("Processing page #{page_num + 1}/#{n_pages}")

            # Load specific page at configured DPI
            page_image = Vips::Image.new_from_file(
              pdf_file.path + "[page=#{page_num},dpi=#{Config::DPI}]",
              access: :sequential
            )

            # Create temp file for this page
            temp_image = Tempfile.new(["page_#{page_num.to_s.rjust(4, '0')}", '.png'])

            # Save as PNG with optimization
            page_image.write_to_file(temp_image.path, compression: 9)

            image_files << temp_image
            @logger.info("Page #{page_num + 1} converted successfully")
          rescue => e
            errors << "Page #{page_num + 1}: #{e.message}"
            @logger.error("Failed to process page #{page_num + 1}: #{e.message}")
          end
        end
      end

      # Wait for all pages to complete
      promises.each(&:wait)
      pool.shutdown
      pool.wait_for_termination(30)

      # Check for errors
      unless errors.empty?
        # Clean up any successfully converted files
        image_files.each { |f| f.close! rescue nil }
        raise "Failed to convert some pages: #{errors.join('; ')}"
      end

      # Sort files by page number
      sorted_files = image_files.to_a.sort_by do |file|
        match = file.path.match(/page_(\d+)/)
        match ? match[1].to_i : 0
      end

      @logger.info("Successfully converted #{sorted_files.length} pages")
      sorted_files

    rescue => e
      raise "Failed to convert PDF: #{e.message}"
    end
  end

  def upload_images_to_s3_with_retry(image_files, destination_url)
    @logger.info("Uploading #{image_files.length} images to S3")

    # Parse S3 destination URL
    destination_uri = URI(destination_url)

    if destination_uri.scheme == 's3'
      # Parse s3://bucket/prefix format
      bucket = destination_uri.host
      prefix = destination_uri.path.sub(/^\//, '').gsub(/\/$/, '')
    else
      raise "Only s3:// URLs are supported for destination"
    end

    # Create S3 client with proper configuration
    s3_client = if @is_localstack
      # Use host.docker.internal for SAM local, otherwise use provided endpoint or localhost
      if ENV['AWS_SAM_LOCAL'] == 'true'
        endpoint = ENV['AWS_ENDPOINT_URL'] || 'http://host.docker.internal:4566'
      else
        endpoint = ENV['AWS_ENDPOINT_URL'] || 'http://localhost:4566'
      end

      Aws::S3::Client.new(
        endpoint: endpoint,
        access_key_id: 'test',
        secret_access_key: 'test',
        region: 'us-east-1',
        force_path_style: true
      )
    else
      Aws::S3::Client.new(region: ENV['AWS_REGION'] || 'us-east-1')
    end

    uploaded_urls = []

    image_files.each_with_index do |image_file, index|
      page_num = index + 1
      image_filename = "page_#{page_num.to_s.rjust(4, '0')}.png"

      # Build the S3 key
      key = prefix.empty? ? image_filename : "#{prefix}/#{image_filename}"
      s3_url = "s3://#{bucket}/#{key}"

      # Upload with retry logic
      success = false
      retries = 0
      max_retries = 3

      while !success && retries < max_retries
        begin
          @logger.info("Uploading page #{page_num} to: #{s3_url} (attempt #{retries + 1})")

          # Upload to S3
          File.open(image_file.path, 'rb') do |file|
            s3_client.put_object(
              bucket: bucket,
              key: key,
              body: file,
              content_type: 'image/png'
            )
          end

          success = true
          uploaded_urls << s3_url
          @logger.info("Page #{page_num} uploaded successfully to S3")

        rescue => e
          retries += 1
          if retries < max_retries
            sleep_time = 2 ** retries  # Exponential backoff
            @logger.warn("Upload failed for page #{page_num}: #{e.message}. Retrying in #{sleep_time}s...")
            sleep(sleep_time)
          else
            raise "Failed to upload image #{page_num} after #{max_retries} attempts: #{e.message}"
          end
        end
      end
    end

    uploaded_urls
  end

  def send_webhook_with_retry(webhook_url, payload, max_retries: Config::WEBHOOK_RETRIES)
    @logger.info("Sending webhook notification to: #{webhook_url}")

    retries = 0
    success = false

    while !success && retries < max_retries
      begin
        uri = URI(webhook_url)

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['User-Agent'] = 'PDFProcessor/1.0'
        request.body = payload.to_json

        response = Net::HTTP.start(uri.host, uri.port,
                                  use_ssl: uri.scheme == 'https',
                                  read_timeout: Config::WEBHOOK_TIMEOUT,
                                  open_timeout: 5) do |http|
          http.request(request)
        end

        if response.is_a?(Net::HTTPSuccess)
          @logger.info("Webhook notification sent successfully")
          @metrics.publish('WebhookSuccess', 1)
          success = true
        else
          raise "HTTP #{response.code} - #{response.message}"
        end

      rescue => e
        retries += 1
        if retries < max_retries
          sleep_time = 2 ** retries  # Exponential backoff
          @logger.warn("Webhook failed: #{e.message}. Retrying in #{sleep_time}s...")
          sleep(sleep_time)
        else
          @logger.error("Failed to send webhook after #{max_retries} attempts: #{e.message}")
          @metrics.publish('WebhookFailures', 1)
          raise "Webhook notification failed after #{max_retries} attempts"
        end
      end
    end
  end

  def cleanup_temp_files(pdf_file, image_files)
    @logger.info("Cleaning up #{1 + image_files.length} temporary files")

    # Close and delete PDF temp file
    pdf_file&.close! rescue nil

    # Close and delete all image temp files
    image_files.each do |image_file|
      image_file&.close! rescue nil
    end
  end

  def configure_for_localstack
    # Use host.docker.internal for SAM local, otherwise use provided endpoint or localhost
    if ENV['AWS_SAM_LOCAL'] == 'true'
      endpoint = ENV['AWS_ENDPOINT_URL'] || 'http://host.docker.internal:4566'
    else
      endpoint = ENV['AWS_ENDPOINT_URL'] || 'http://localhost:4566'
    end

    # Configure global AWS settings
    Aws.config.update(
      endpoint: endpoint,
      access_key_id: 'test',
      secret_access_key: 'test',
      region: 'us-east-1'
    )

    # Configure S3-specific settings separately
    Aws.config[:s3] = {
      force_path_style: true,
      endpoint: endpoint
    }

    @logger.info("Configured for LocalStack at #{endpoint}")
  end

  def error_response(status_code, message)
    {
      statusCode: status_code,
      headers: {
        'Content-Type' => 'application/json'
      },
      body: {
        status: 'error',
        message: message,
        request_id: @context&.respond_to?(:aws_request_id) ? @context.aws_request_id :
                    @context&.respond_to?(:request_id) ? @context.request_id : nil
      }.to_json
    }
  end
end

def lambda_handler(event:, context:)
  processor = PDFProcessor.new(event, context)
  processor.process
end
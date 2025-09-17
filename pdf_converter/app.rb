require 'json'
require 'httparty'
require 'jwt'

# Set up libvips library path before requiring vips
ENV['LD_LIBRARY_PATH'] = "/usr/local/lib:#{ENV['LD_LIBRARY_PATH']}"
ENV['VIPS_LIBRARY_PATH'] = '/usr/local/lib'

# Try to load libvips with explicit path
begin
  require 'vips'
rescue LoadError => e
  # If standard load fails, try with explicit library path
  ENV['RUBY_DL_LIBRARY_PATH'] = '/usr/local/lib'
  require 'vips'
end

require 'net/http'
require 'uri'
require 'tempfile'
require 'fileutils'
require 'aws-sdk-secretsmanager'

class PDFProcessor
  def initialize(event, context)
    @event = event
    @context = context
    @logger = context.respond_to?(:logger) ? context.logger : Logger.new(STDOUT)
  end

  def process
    begin
      # Parse request
      body = parse_request_body
      headers = @event['headers'] || @event[:headers] || {}

      # Authenticate
      unless authenticate_request(headers)
        return error_response(401, 'Unauthorized')
      end

      # Validate payload
      validation_error = validate_payload(body)
      return validation_error if validation_error

      # Process PDF
      @logger.info("Starting PDF processing for source: #{body['source']}")

      # Download PDF from source URL
      pdf_file = download_pdf(body['source'])

      # Convert PDF to images
      image_files = convert_pdf_to_images(pdf_file)

      # Upload images to destination
      uploaded_urls = upload_images_to_s3(image_files, body['destination'])

      # Send webhook notification if provided
      if body['webhook']
        send_webhook_notification(body['webhook'], {
          status: 'success',
          source: body['source'],
          destination: body['destination'],
          images_count: uploaded_urls.length,
          image_urls: uploaded_urls
        })
      end

      # Clean up temp files
      cleanup_temp_files(pdf_file, image_files)

      # Return success response
      {
        statusCode: 200,
        headers: {
          'Content-Type' => 'application/json'
        },
        body: {
          status: 'success',
          message: 'PDF processed successfully',
          images_count: uploaded_urls.length,
          image_urls: uploaded_urls
        }.to_json
      }

    rescue StandardError => e
      @logger.error("Error processing PDF: #{e.message}")
      @logger.error(e.backtrace.join("\n"))

      # Attempt to send error webhook if available
      if body && body['webhook']
        begin
          send_webhook_notification(body['webhook'], {
            status: 'error',
            error: e.message,
            source: (body['source'] rescue nil)
          })
        rescue
          # Ignore webhook failures in error handler
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
    if ENV['LOCAL_TESTING'] == 'true' || ENV['AWS_SAM_LOCAL'] == 'true'
      @logger.info("Running in local mode, using local JWT secret")
      return ENV['JWT_SECRET'] || 'local-testing-secret-key'
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
    rescue Aws::SecretsManager::Errors::InvalidRequestException => e
      @logger.error("Invalid request to Secrets Manager: #{e.message}")
      raise "Failed to retrieve JWT secret"
    rescue Aws::SecretsManager::Errors::InvalidParameterException => e
      @logger.error("Invalid parameter: #{e.message}")
      raise "Failed to retrieve JWT secret"
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
      @logger.info("Authenticated request with JWT claims: #{decoded_token[0]}")
      true
    rescue => e
      @logger.error("JWT authentication failed: #{e.class} - #{e.message}")
      false
    end
  end

  def validate_payload(body)
    return error_response(400, 'Missing required field: source') unless body['source']
    return error_response(400, 'Missing required field: destination') unless body['destination']
    return error_response(400, 'Invalid source URL') unless valid_url?(body['source'])
    return error_response(400, 'Invalid destination URL') unless valid_url?(body['destination'])

    if body['webhook'] && !valid_url?(body['webhook'])
      return error_response(400, 'Invalid webhook URL')
    end

    nil
  end

  def valid_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def download_pdf(source_url)
    @logger.info("Downloading PDF from: #{source_url}")

    uri = URI(source_url)
    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      raise "Failed to download PDF: HTTP #{response.code} - #{response.message}"
    end

    # Save to temp file
    temp_pdf = Tempfile.new(['pdf_input', '.pdf'])
    temp_pdf.binmode
    temp_pdf.write(response.body)
    temp_pdf.rewind

    @logger.info("PDF downloaded successfully, size: #{response.body.size} bytes")
    temp_pdf
  end

  def convert_pdf_to_images(pdf_file)
    @logger.info("Converting PDF to images")

    image_files = []

    begin
      # Load PDF with libvips
      # The PDF loader will automatically use pdfium if available
      pdf = Vips::Image.new_from_file(pdf_file.path, access: :sequential)

      # Get number of pages
      n_pages = pdf.get('n-pages')
      @logger.info("PDF has #{n_pages} pages")

      # Process each page
      (0...n_pages).each do |page_num|
        @logger.info("Processing page #{page_num + 1}/#{n_pages}")

        # Load specific page at higher DPI for better quality
        page_image = Vips::Image.new_from_file(
          pdf_file.path + "[page=#{page_num},dpi=150]",
          access: :sequential
        )

        # Create temp file for this page
        temp_image = Tempfile.new(['page', '.png'])

        # Save as PNG
        page_image.write_to_file(temp_image.path)

        image_files << temp_image
        @logger.info("Page #{page_num + 1} converted successfully")
      end

    rescue => e
      # Clean up any created temp files on error
      image_files.each { |f| f.close! rescue nil }
      raise "Failed to convert PDF: #{e.message}"
    end

    @logger.info("Successfully converted #{image_files.length} pages")
    image_files
  end

  def upload_images_to_s3(image_files, destination_url)
    @logger.info("Uploading #{image_files.length} images to S3")

    uploaded_urls = []

    # Parse destination URL to get base path
    destination_uri = URI(destination_url)
    base_path = destination_uri.path.gsub(/\/$/, '')

    image_files.each_with_index do |image_file, index|
      # Construct URL for this specific image
      page_num = index + 1
      image_filename = "page_#{page_num.to_s.rjust(4, '0')}.png"

      # Create full URL for this image
      image_url = destination_url.gsub(/\/$/, '') + "/#{image_filename}"

      @logger.info("Uploading page #{page_num} to: #{image_url}")

      # Upload image using PUT request to signed URL
      uri = URI(image_url)

      File.open(image_file.path, 'rb') do |file|
        request = Net::HTTP::Put.new(uri)
        request.body = file.read
        request['Content-Type'] = 'image/png'

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request)
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise "Failed to upload image #{page_num}: HTTP #{response.code} - #{response.message}"
        end
      end

      uploaded_urls << image_url.split('?').first  # Remove query params from URL
      @logger.info("Page #{page_num} uploaded successfully")
    end

    uploaded_urls
  end

  def send_webhook_notification(webhook_url, payload)
    @logger.info("Sending webhook notification to: #{webhook_url}")

    uri = URI(webhook_url)

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end

    if response.is_a?(Net::HTTPSuccess)
      @logger.info("Webhook notification sent successfully")
    else
      @logger.warn("Webhook notification failed: HTTP #{response.code} - #{response.message}")
    end

  rescue => e
    @logger.error("Failed to send webhook: #{e.message}")
  end

  def cleanup_temp_files(pdf_file, image_files)
    @logger.info("Cleaning up temporary files")

    # Close and delete PDF temp file
    pdf_file.close! rescue nil

    # Close and delete all image temp files
    image_files.each do |image_file|
      image_file.close! rescue nil
    end
  end

  def error_response(status_code, message)
    {
      statusCode: status_code,
      headers: {
        'Content-Type' => 'application/json'
      },
      body: {
        status: 'error',
        message: message
      }.to_json
    }
  end
end

def lambda_handler(event:, context:)
  processor = PDFProcessor.new(event, context)
  processor.process
end
require 'json'
require 'test/unit'
require 'mocha/test_unit'
require 'jwt'
require 'tempfile'
require 'base64'
require 'aws-sdk-secretsmanager'

# Stub environment variables for testing
ENV['JWT_SECRET_NAME'] ||= 'test/jwt-secret'
ENV['AWS_REGION'] ||= 'us-east-1'

require_relative '../../pdf_converter/app'

class PDFProcessorTest < Test::Unit::TestCase
  def setup
    @jwt_secret = 'test-secret'
    @valid_token = JWT.encode({ sub: 'test-user', exp: Time.now.to_i + 3600 }, @jwt_secret, 'HS256')

    # Mock AWS Secrets Manager client and response
    mock_secrets_response
  end

  def teardown
    # Clean up any stubs/mocks - reset all mocks after each test
    Net::HTTP.unstub(:get_response) if Net::HTTP.respond_to?(:unstub)
    Net::HTTP.unstub(:start) if Net::HTTP.respond_to?(:unstub)
    Vips::Image.unstub(:new_from_file) if Vips::Image.respond_to?(:unstub)
    Mocha::Mockery.instance.teardown
  end

  def mock_secrets_response
    # Mock the Secrets Manager client
    @mock_secrets_client = mock('secrets_client')
    Aws::SecretsManager::Client.stubs(:new).returns(@mock_secrets_client)

    # Mock successful secret retrieval
    @mock_response = mock('secret_response')
    @mock_response.stubs(:secret_string).returns({ jwt_secret: @jwt_secret }.to_json)
    @mock_secrets_client.stubs(:get_secret_value).returns(@mock_response)
  end

  def valid_event
    {
      body: {
        source: 'https://example.com/test.pdf',
        destination: 'https://example.com/output/',
        webhook: 'https://example.com/webhook'
      }.to_json,
      resource: '/process',
      path: '/process',
      httpMethod: 'POST',
      isBase64Encoded: false,
      headers: {
        'Authorization' => "Bearer #{@valid_token}",
        'Content-Type' => 'application/json'
      },
      requestContext: mock_request_context
    }
  end

  def mock_request_context
    {
      accountId: '123456789012',
      resourceId: '123456',
      stage: 'prod',
      requestId: 'test-request-id',
      requestTime: Time.now.to_s,
      requestTimeEpoch: Time.now.to_i * 1000,
      identity: {
        sourceIp: '127.0.0.1',
        userAgent: 'Test User Agent'
      },
      path: '/prod/process',
      resourcePath: '/process',
      httpMethod: 'POST',
      apiId: '1234567890',
      protocol: 'HTTP/1.1'
    }
  end

  def mock_context
    context = Object.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::WARN  # Reduce test output noise
    context.stubs(:logger).returns(logger)
    context
  end

  def test_missing_authorization
    event = valid_event
    event[:headers].delete('Authorization')

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(401, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_equal('Unauthorized', body['message'])
  end

  def test_invalid_jwt
    event = valid_event
    event[:headers]['Authorization'] = 'Bearer invalid-token'

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(401, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_equal('Unauthorized', body['message'])
  end

  def test_expired_jwt
    expired_token = JWT.encode(
      { sub: 'test-user', exp: Time.now.to_i - 3600 },
      @jwt_secret,
      'HS256'
    )
    event = valid_event
    event[:headers]['Authorization'] = "Bearer #{expired_token}"

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(401, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_equal('Unauthorized', body['message'])
  end

  def test_missing_source
    event = valid_event
    body = JSON.parse(event[:body])
    body.delete('source')
    event[:body] = body.to_json

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(400, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_equal('Missing required field: source', body['message'])
  end

  def test_missing_destination
    event = valid_event
    body = JSON.parse(event[:body])
    body.delete('destination')
    event[:body] = body.to_json

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(400, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_equal('Missing required field: destination', body['message'])
  end

  def test_invalid_source_url
    event = valid_event
    body = JSON.parse(event[:body])
    body['source'] = 'not-a-url'
    event[:body] = body.to_json

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(400, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_equal('Invalid source URL', body['message'])
  end

  def test_invalid_destination_url
    event = valid_event
    body = JSON.parse(event[:body])
    body['destination'] = 'not-a-url'
    event[:body] = body.to_json

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(400, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_equal('Invalid destination URL', body['message'])
  end

  def test_invalid_webhook_url
    event = valid_event
    body = JSON.parse(event[:body])
    body['webhook'] = 'not-a-url'
    event[:body] = body.to_json

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(400, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_equal('Invalid webhook URL', body['message'])
  end

  def test_base64_encoded_body_parsing
    event = valid_event
    original_body = event[:body]
    event[:body] = Base64.encode64(event[:body])
    event[:isBase64Encoded] = true

    # Mock successful PDF download to verify base64 parsing works
    pdf_response = Net::HTTPSuccess.new('1.1', '200', 'OK')
    pdf_response.stubs(:body).returns('fake-pdf-content')
    Net::HTTP.stubs(:get_response).returns(pdf_response)

    # Mock Vips PDF processing
    mock_pdf = mock('pdf')
    mock_pdf.stubs(:get).with('n-pages').returns(1)
    Vips::Image.stubs(:new_from_file).returns(mock_pdf)
    mock_pdf.stubs(:write_to_file).returns(true)

    # Mock S3 uploads
    upload_response = Net::HTTPSuccess.new('1.1', '200', 'OK')
    http_mock = mock('http')
    http_mock.stubs(:request).returns(upload_response)
    Net::HTTP.stubs(:start).yields(http_mock).returns(upload_response)

    result = lambda_handler(event: event, context: mock_context)

    # Verify that base64 decoding worked and request was processed
    assert_equal(200, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('success', body['status'])
  ensure
    # Clean up mocks immediately after this test
    Net::HTTP.unstub(:get_response) rescue nil
    Net::HTTP.unstub(:start) rescue nil
    Vips::Image.unstub(:new_from_file) rescue nil
  end

  def test_download_failure_with_base64_body
    event = valid_event
    event[:body] = Base64.encode64(event[:body])
    event[:isBase64Encoded] = true

    # Mock the download failure
    mock_response = mock('response')
    mock_response.stubs(:is_a?).with(Net::HTTPSuccess).returns(false)
    mock_response.stubs(:code).returns('404')
    mock_response.stubs(:message).returns('Not Found')
    Net::HTTP.stubs(:get_response).returns(mock_response)

    result = lambda_handler(event: event, context: mock_context)

    # Should fail at download stage with proper error
    assert_equal(500, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_match(/Failed to download PDF/, body['message'])
  end

  def test_successful_processing_with_mocks
    event = valid_event

    # Mock PDF download
    pdf_response = Net::HTTPSuccess.new('1.1', '200', 'OK')
    pdf_response.stubs(:body).returns('fake-pdf-content')
    Net::HTTP.stubs(:get_response).returns(pdf_response)

    # Mock Vips PDF processing
    mock_pdf = mock('pdf')
    mock_pdf.stubs(:get).with('n-pages').returns(2)
    Vips::Image.stubs(:new_from_file).returns(mock_pdf)

    # Mock image writing
    mock_pdf.stubs(:write_to_file).returns(true)

    # Mock S3 uploads
    upload_response = Net::HTTPSuccess.new('1.1', '200', 'OK')
    http_mock = mock('http')
    http_mock.stubs(:request).returns(upload_response)
    Net::HTTP.stubs(:start).yields(http_mock).returns(upload_response)

    # Mock webhook notification - not needed since we're mocking Net::HTTP.start

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(200, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('success', body['status'])
    assert_equal('PDF processed successfully', body['message'])
  end

  def test_pdf_download_failure
    event = valid_event

    # Mock failed PDF download
    mock_response = mock('response')
    mock_response.stubs(:is_a?).with(Net::HTTPSuccess).returns(false)
    mock_response.stubs(:code).returns('404')
    mock_response.stubs(:message).returns('Not Found')
    Net::HTTP.stubs(:get_response).returns(mock_response)

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(500, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_match(/Failed to download PDF/, body['message'])
  end

  def test_empty_body
    event = valid_event
    event[:body] = nil

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(401, result[:statusCode])  # Will fail at auth since no body
  end

  def test_invalid_json_body
    event = valid_event
    event[:body] = 'not-valid-json'

    result = lambda_handler(event: event, context: mock_context)

    assert_equal(500, result[:statusCode])
    body = JSON.parse(result[:body])
    assert_equal('error', body['status'])
    assert_match(/Invalid JSON/, body['message'])
  end
end
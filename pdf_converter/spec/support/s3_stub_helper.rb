# frozen_string_literal: true

require 'webmock/rspec'

# S3 stubbing helper methods for testing AWS S3 operations
module S3StubHelper
  # Generate a valid minimal PDF content for testing
  #
  # @return [String] Valid PDF content
  def minimal_pdf_content
    "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n>>\nendobj\nxref\n0 1\n0000000000 65535 f \ntrailer\n<<\n/Size 1\n/Root 1 0 R\n>>\nstartxref\n9\n%%EOF"
  end

  # Stub a successful S3 GET request
  #
  # @param url [String] The S3 URL to stub
  # @param body [String] The response body (defaults to minimal PDF)
  # @param headers [Hash] Additional response headers
  # @return [WebMock::RequestStub]
  def stub_s3_get_success(url, body: minimal_pdf_content, headers: {})
    default_headers = { 'Content-Type' => 'application/pdf' }
    stub_request(:get, url)
      .to_return(status: 200, body: body, headers: default_headers.merge(headers))
  end

  # Stub a successful S3 PUT request
  #
  # @param url [String] The S3 URL to stub
  # @param etag [String] The ETag to return (defaults to a test ETag)
  # @return [WebMock::RequestStub]
  def stub_s3_put_success(url, etag: '"test-etag-123"')
    stub_request(:put, url)
      .to_return(status: 200, body: '', headers: { 'ETag' => etag })
  end

  # Stub an S3 error response
  #
  # @param url [String] The S3 URL to stub
  # @param status [Integer] The HTTP status code (e.g., 404, 500)
  # @param body [String] The error response body
  # @return [WebMock::RequestStub]
  def stub_s3_error(url, status: 404, body: 'Not Found')
    stub_request(:get, url)
      .to_return(status: status, body: body)
  end

  # Stub an S3 timeout error
  #
  # @param url [String] The S3 URL to stub
  # @param times [Integer] Number of times to timeout (default: 1)
  # @return [WebMock::RequestStub]
  def stub_s3_timeout(url, times: 1)
    stub_request(:get, url).to_timeout.times(times)
  end

  # Stub an S3 request with multiple sequential responses
  #
  # @param url [String] The S3 URL to stub
  # @param responses [Array<Hash>] Array of response hashes with :status, :body, :headers
  # @return [WebMock::RequestStub]
  #
  # @example
  #   stub_s3_sequential(url, [
  #     { status: 500, body: 'Error' },
  #     { status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' } }
  #   ])
  def stub_s3_sequential(url, responses)
    stub = stub_request(:get, url)

    responses.each_with_index do |response, index|
      if index < responses.length - 1
        stub = stub.to_return(
          status: response[:status],
          body: response[:body] || '',
          headers: response[:headers] || {}
        ).then
      else
        stub.to_return(
          status: response[:status],
          body: response[:body] || '',
          headers: response[:headers] || {}
        )
      end
    end

    stub
  end

  # Stub pattern matching for multiple S3 URLs
  #
  # @param pattern [Regexp] The URL pattern to match
  # @param status [Integer] The HTTP status code
  # @param body [String] The response body
  # @return [WebMock::RequestStub]
  def stub_s3_pattern(pattern, status: 200, body: minimal_pdf_content)
    stub_request(:get, pattern)
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/pdf' })
  end

  # Create a valid S3 pre-signed URL for testing
  #
  # @param bucket [String] The S3 bucket name
  # @param key [String] The S3 object key
  # @param query_params [Hash] Additional query parameters
  # @return [String] A valid-looking S3 URL
  def s3_presigned_url(bucket: 'test-bucket', key: 'test-file.pdf', query_params: {})
    default_params = {
      'X-Amz-Algorithm' => 'AWS4-HMAC-SHA256',
      'X-Amz-Credential' => 'AKIAIOSFODNN7EXAMPLE/20230101/us-east-1/s3/aws4_request',
      'X-Amz-Date' => '20230101T000000Z',
      'X-Amz-Expires' => '3600',
      'X-Amz-SignedHeaders' => 'host',
      'X-Amz-Signature' => 'test-signature'
    }

    params = default_params.merge(query_params)
    query_string = params.map { |k, v| "#{k}=#{v}" }.join('&')

    "https://#{bucket}.s3.amazonaws.com/#{key}?#{query_string}"
  end
end

# Include S3 stub helper in RSpec
RSpec.configure do |config|
  config.include S3StubHelper
end

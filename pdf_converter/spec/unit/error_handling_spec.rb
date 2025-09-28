# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require_relative '../../pdf_downloader'

RSpec.describe 'Error Handling and Retry Logic' do
  let(:valid_s3_url) { 'https://s3.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }
  let(:pdf_content) { "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n>>\nendobj\nxref\n0 1\n0000000000 65535 f \ntrailer\n<<\n/Size 1\n/Root 1 0 R\n>>\nstartxref\n9\n%%EOF" }

  before do
    WebMock.disable_net_connect!
  end

  after do
    WebMock.reset!
  end

  describe 'retry logic for transient failures' do
    it 'retries on timeout errors up to 3 times' do
      downloader = PdfDownloader.new

      # First two requests timeout, third succeeds
      stub_request(:get, valid_s3_url)
        .to_timeout.times(2)
        .then
        .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be true
      expect(result[:content]).to eq(pdf_content)
      expect(WebMock).to have_requested(:get, valid_s3_url).times(3)
    end

    it 'retries on 5xx server errors' do
      downloader = PdfDownloader.new

      # First request returns 500, second succeeds
      stub_request(:get, valid_s3_url)
        .to_return(status: 500, body: 'Internal Server Error')
        .then
        .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be true
      expect(result[:content]).to eq(pdf_content)
      expect(WebMock).to have_requested(:get, valid_s3_url).times(2)
    end

    it 'does not retry on 4xx client errors' do
      downloader = PdfDownloader.new

      stub_request(:get, valid_s3_url)
        .to_return(status: 404, body: 'Not Found')

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be false
      expect(result[:error]).to include('404')
      expect(WebMock).to have_requested(:get, valid_s3_url).times(1)
    end

    it 'fails after maximum retry attempts' do
      downloader = PdfDownloader.new

      stub_request(:get, valid_s3_url).to_timeout.times(4)

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be false
      expect(result[:error]).to include('timeout')
      expect(WebMock).to have_requested(:get, valid_s3_url).times(3) # Max retries
    end

    it 'includes retry count in error messages' do
      downloader = PdfDownloader.new

      stub_request(:get, valid_s3_url).to_timeout.times(3)

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be false
      expect(result[:error]).to include('after 3 attempts')
    end
  end

  describe 'specific error handling scenarios' do
    it 'handles connection refused errors' do
      downloader = PdfDownloader.new

      stub_request(:get, valid_s3_url).to_raise(Errno::ECONNREFUSED)

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be false
      expect(result[:error]).to include('Connection refused')
    end

    it 'handles DNS resolution errors' do
      downloader = PdfDownloader.new

      stub_request(:get, valid_s3_url).to_raise(SocketError.new('getaddrinfo: nodename nor servname provided'))

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be false
      expect(result[:error]).to include('DNS resolution failed')
    end

    it 'handles SSL errors' do
      downloader = PdfDownloader.new

      stub_request(:get, valid_s3_url).to_raise(OpenSSL::SSL::SSLError.new('SSL_connect error'))

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be false
      expect(result[:error]).to include('SSL connection failed')
    end

    it 'handles memory exhaustion during large downloads' do
      downloader = PdfDownloader.new

      stub_request(:get, valid_s3_url).to_raise(NoMemoryError.new('failed to allocate memory'))

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be false
      expect(result[:error]).to include('Memory exhaustion')
    end
  end

  describe 'retry behavior verification' do
    it 'performs correct number of retry attempts' do
      downloader = PdfDownloader.new

      stub_request(:get, valid_s3_url)
        .to_return(status: 500, body: 'Server Error')
        .then
        .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be true
      expect(WebMock).to have_requested(:get, valid_s3_url).times(2)
    end

    it 'successfully downloads large files' do
      downloader = PdfDownloader.new
      large_content = "%PDF-1.4\n" + "x" * (5 * 1024 * 1024) + "\n%%EOF"

      stub_request(:get, valid_s3_url)
        .to_return(status: 200, body: large_content, headers: { 'Content-Type' => 'application/pdf' })

      result = downloader.download(valid_s3_url)

      expect(result[:success]).to be true
      expect(result[:content].length).to be > (5 * 1024 * 1024)
    end

    it 'handles sensitive URLs properly' do
      downloader = PdfDownloader.new
      sensitive_url = 'https://s3.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=SENSITIVE'

      stub_request(:get, sensitive_url)
        .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })

      result = downloader.download(sensitive_url)

      expect(result[:success]).to be true
      expect(WebMock).to have_requested(:get, sensitive_url).once
    end
  end
end
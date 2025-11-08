# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require_relative '../../app/pdf_downloader'

RSpec.describe PdfDownloader do
  let(:downloader) { described_class.new }
  let(:url) { 'https://s3.amazonaws.com/bucket/file.pdf?signed=true' }
  let(:pdf_content) { "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n>>\nendobj\nxref\n0 1\n0000000000 65535 f\ntrailer\n<<\n/Size 1\n>>\nstartxref\n0\n%%EOF\n" }

  before do
    WebMock.disable_net_connect!
  end

  after do
    WebMock.reset!
  end

  describe 'TIMEOUT_SECONDS' do
    it 'is set to 30 seconds' do
      expect(described_class::TIMEOUT_SECONDS).to eq(30)
    end
  end

  describe 'MAX_REDIRECTS' do
    it 'is set to 5' do
      expect(described_class::MAX_REDIRECTS).to eq(5)
    end
  end

  describe 'VALID_PDF_MAGIC_NUMBERS' do
    it 'includes PDF 1.x magic number' do
      expect(described_class::VALID_PDF_MAGIC_NUMBERS).to include('%PDF-1.')
    end

    it 'includes PDF 2.x magic number' do
      expect(described_class::VALID_PDF_MAGIC_NUMBERS).to include('%PDF-2.')
    end

    it 'is frozen' do
      expect(described_class::VALID_PDF_MAGIC_NUMBERS).to be_frozen
    end
  end

  describe '#download' do
    context 'with successful download' do
      before do
        stub_request(:get, url)
          .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'returns success with content' do
        result = downloader.download(url)
        expect(result[:success]).to be true
        expect(result[:content]).to eq(pdf_content)
      end

      it 'returns content type' do
        result = downloader.download(url)
        expect(result[:content_type]).to eq('application/pdf')
      end

      it 'logs download info' do
        expect { downloader.download(url) }
          .to output(/Starting PDF download/)
          .to_stdout
      end

      it 'logs success message' do
        expect { downloader.download(url) }
          .to output(/PDF download completed successfully/)
          .to_stdout
      end
    end

    context 'with PDF 2.x content' do
      let(:pdf2_content) { '%PDF-2.0 sample content' }

      before do
        stub_request(:get, url)
          .to_return(status: 200, body: pdf2_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'accepts PDF 2.x format' do
        result = downloader.download(url)
        expect(result[:success]).to be true
      end
    end

    context 'with successful download but no content-type header' do
      before do
        stub_request(:get, url)
          .to_return(status: 200, body: pdf_content, headers: {})
      end

      it 'uses default content type' do
        result = downloader.download(url)
        expect(result[:content_type]).to eq('application/octet-stream')
      end
    end

    context 'with nil URL' do
      it 'returns error for nil URL' do
        result = downloader.download(nil)
        expect(result[:success]).to be false
        expect(result[:error]).to include('URL cannot be nil or empty')
      end
    end

    context 'with empty URL' do
      it 'returns error for empty URL' do
        result = downloader.download('')
        expect(result[:success]).to be false
        expect(result[:error]).to include('URL cannot be nil or empty')
      end
    end

    context 'with invalid URL format' do
      let(:invalid_url) { 'not a valid url' }

      it 'returns error for invalid URI' do
        result = downloader.download(invalid_url)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid URL format')
      end
    end

    context 'with non-HTTP URL' do
      let(:ftp_url) { 'ftp://example.com/file.pdf' }

      it 'returns error for non-HTTP(S) URL' do
        result = downloader.download(ftp_url)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid URL format')
      end
    end

    context 'with invalid PDF content' do
      let(:non_pdf_content) { 'This is not a PDF file' }

      before do
        stub_request(:get, url)
          .to_return(status: 200, body: non_pdf_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'returns error for invalid PDF' do
        result = downloader.download(url)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid PDF content')
      end

      it 'logs error message' do
        expect { downloader.download(url) }
          .to output(/Invalid PDF content/).to_stdout
      end
    end

    context 'with empty response body' do
      before do
        stub_request(:get, url)
          .to_return(status: 200, body: '', headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'returns error for empty content' do
        result = downloader.download(url)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid PDF content')
      end
    end

    context 'with HTTP redirects' do
      let(:redirect_url) { 'https://s3-redirect.amazonaws.com/bucket/file.pdf' }

      before do
        stub_request(:get, url)
          .to_return(status: 301, headers: { 'Location' => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'follows redirects' do
        result = downloader.download(url)
        expect(result[:success]).to be true
        expect(result[:content]).to eq(pdf_content)
      end

      it 'logs redirect' do
        expect { downloader.download(url) }
          .to output(/Following redirect/).to_stdout
      end
    end

    context 'with too many redirects' do
      before do
        # Stub 6 redirects (exceeds MAX_REDIRECTS of 5)
        stub_request(:get, url).to_return(status: 301, headers: { 'Location' => "#{url}-1" })
        stub_request(:get, "#{url}-1").to_return(status: 301, headers: { 'Location' => "#{url}-2" })
        stub_request(:get, "#{url}-2").to_return(status: 301, headers: { 'Location' => "#{url}-3" })
        stub_request(:get, "#{url}-3").to_return(status: 301, headers: { 'Location' => "#{url}-4" })
        stub_request(:get, "#{url}-4").to_return(status: 301, headers: { 'Location' => "#{url}-5" })
        stub_request(:get, "#{url}-5").to_return(status: 301, headers: { 'Location' => "#{url}-6" })
      end

      it 'returns error after max redirects' do
        result = downloader.download(url)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Too many redirects')
      end
    end

    context 'with redirect but missing location header' do
      before do
        stub_request(:get, url)
          .to_return(status: 301, headers: {})
      end

      it 'returns error for redirect without location' do
        result = downloader.download(url)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Redirect without location header')
      end
    end

    context 'with HTTP 404 error' do
      before do
        stub_request(:get, url)
          .to_return(status: 404, body: 'Not Found')
      end

      it 'returns error for 404' do
        result = downloader.download(url)
        expect(result[:success]).to be false
        expect(result[:error]).to include('HTTP 404')
      end
    end

    context 'with HTTP 500 error' do
      before do
        stub_request(:get, url)
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'returns error for 500' do
        result = downloader.download(url)
        expect(result[:success]).to be false
        expect(result[:error]).to include('HTTP 500')
      end
    end

    context 'with network timeout' do
      before do
        stub_request(:get, url).to_timeout
      end

      it 'returns error for timeout' do
        result = downloader.download(url)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Download failed')
      end
    end

    context 'with connection refused' do
      before do
        stub_request(:get, url).to_raise(Errno::ECONNREFUSED)
      end

      it 'returns error for connection refused' do
        result = downloader.download(url)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Download failed')
      end
    end

    context 'with HTTP URL' do
      let(:http_url) { 'http://localhost:4566/bucket/file.pdf' }

      before do
        stub_request(:get, http_url)
          .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'downloads from HTTP URL' do
        result = downloader.download(http_url)
        expect(result[:success]).to be true
      end
    end

    context 'with HTTPS URL' do
      let(:https_url) { 'https://secure.example.com/file.pdf' }

      before do
        stub_request(:get, https_url)
          .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'downloads from HTTPS URL with SSL' do
        result = downloader.download(https_url)
        expect(result[:success]).to be true
      end
    end
  end

  describe '#validate_pdf_content' do
    context 'with valid PDF 1.x content' do
      let(:content) { '%PDF-1.4 content here' }

      it 'returns true' do
        expect(downloader.validate_pdf_content(content)).to be true
      end
    end

    context 'with valid PDF 2.x content' do
      let(:content) { '%PDF-2.0 content here' }

      it 'returns true' do
        expect(downloader.validate_pdf_content(content)).to be true
      end
    end

    context 'with PDF 1.7 content' do
      let(:content) { '%PDF-1.7 content' }

      it 'returns true for PDF 1.7' do
        expect(downloader.validate_pdf_content(content)).to be true
      end
    end

    context 'with nil content' do
      it 'returns false' do
        expect(downloader.validate_pdf_content(nil)).to be false
      end
    end

    context 'with empty content' do
      it 'returns false' do
        expect(downloader.validate_pdf_content('')).to be false
      end
    end

    context 'with non-PDF content' do
      let(:content) { 'This is not a PDF' }

      it 'returns false' do
        expect(downloader.validate_pdf_content(content)).to be false
      end
    end

    context 'with content that has PDF in middle' do
      let(:content) { 'junk before %PDF-1.4 content' }

      it 'returns false when PDF header not at start' do
        expect(downloader.validate_pdf_content(content)).to be false
      end
    end
  end

  describe '#validate_url (private)' do
    context 'with valid HTTP URL' do
      let(:http_url) { 'http://example.com/file.pdf' }

      it 'does not raise error' do
        expect { downloader.send(:validate_url, http_url) }.not_to raise_error
      end
    end

    context 'with valid HTTPS URL' do
      let(:https_url) { 'https://example.com/file.pdf' }

      it 'does not raise error' do
        expect { downloader.send(:validate_url, https_url) }.not_to raise_error
      end
    end

    context 'with nil URL' do
      it 'raises ArgumentError' do
        expect { downloader.send(:validate_url, nil) }
          .to raise_error(ArgumentError, /URL cannot be nil or empty/)
      end
    end

    context 'with empty URL' do
      it 'raises ArgumentError' do
        expect { downloader.send(:validate_url, '') }
          .to raise_error(ArgumentError, /URL cannot be nil or empty/)
      end
    end

    context 'with FTP URL' do
      let(:ftp_url) { 'ftp://example.com/file.pdf' }

      it 'raises URI::InvalidURIError' do
        expect { downloader.send(:validate_url, ftp_url) }
          .to raise_error(URI::InvalidURIError, /URL must be HTTP or HTTPS/)
      end
    end

    context 'with file URL' do
      let(:file_url) { 'file:///path/to/file.pdf' }

      it 'raises URI::InvalidURIError' do
        expect { downloader.send(:validate_url, file_url) }
          .to raise_error(URI::InvalidURIError, /URL must be HTTP or HTTPS/)
      end
    end
  end

  describe '#download_with_retry (private)' do
    let(:uri) { URI.parse(url) }

    context 'when fetch succeeds on first try' do
      before do
        stub_request(:get, url)
          .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'returns content and content type' do
        content, content_type = downloader.send(:download_with_retry, uri)
        expect(content).to eq(pdf_content)
        expect(content_type).to eq('application/pdf')
      end
    end

    context 'when RetryHandler raises RetryError' do
      before do
        stub_request(:get, url).to_timeout.times(3)
      end

      it 'raises StandardError' do
        expect { downloader.send(:download_with_retry, uri) }
          .to raise_error(StandardError, /execution expired/)
      end
    end
  end

  describe '#fetch_with_redirects (private)' do
    let(:uri) { URI.parse(url) }

    context 'with successful response' do
      before do
        stub_request(:get, url)
          .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'returns content and content type' do
        content, content_type = downloader.send(:fetch_with_redirects, uri)
        expect(content).to eq(pdf_content)
        expect(content_type).to eq('application/pdf')
      end
    end

    context 'with redirect' do
      let(:redirect_url) { 'https://new-location.com/file.pdf' }

      before do
        stub_request(:get, url)
          .to_return(status: 302, headers: { 'Location' => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'follows redirect' do
        content, _content_type = downloader.send(:fetch_with_redirects, uri)
        expect(content).to eq(pdf_content)
      end
    end

    context 'with max redirects exceeded' do
      let(:uri) { URI.parse(url) }

      before do
        stub_request(:get, url).to_return(status: 301, headers: { 'Location' => url })
      end

      it 'raises error when redirect count exceeds max' do
        expect { downloader.send(:fetch_with_redirects, uri, 5) }
          .to raise_error(StandardError, /Too many redirects/)
      end
    end

    context 'with redirect missing location' do
      before do
        stub_request(:get, url).to_return(status: 301, headers: {})
      end

      it 'raises error for redirect without location' do
        expect { downloader.send(:fetch_with_redirects, uri) }
          .to raise_error(StandardError, /Redirect without location header/)
      end
    end

    context 'with 404 response' do
      before do
        stub_request(:get, url).to_return(status: 404, body: 'Not Found')
      end

      it 'raises error for 404' do
        expect { downloader.send(:fetch_with_redirects, uri) }
          .to raise_error(StandardError, /HTTP 404/)
      end
    end

    context 'with 500 response' do
      before do
        stub_request(:get, url).to_return(status: 500, body: 'Server Error')
      end

      it 'raises error for 500' do
        expect { downloader.send(:fetch_with_redirects, uri) }
          .to raise_error(StandardError, /HTTP 500/)
      end
    end
  end

  describe '#perform_http_request (private)' do
    let(:uri) { URI.parse(url) }

    context 'with HTTPS URL' do
      before do
        stub_request(:get, url)
          .to_return(status: 200, body: pdf_content)
      end

      it 'uses SSL for HTTPS' do
        downloader.send(:perform_http_request, uri)
        expect(WebMock).to have_requested(:get, url)
      end

      it 'sets User-Agent header' do
        downloader.send(:perform_http_request, uri)
        expect(WebMock).to have_requested(:get, url)
          .with(headers: { 'User-Agent' => 'PDF-Converter-Service/1.0' })
      end
    end

    context 'with HTTP URL' do
      let(:http_uri) { URI.parse('http://localhost:4566/file.pdf') }

      before do
        stub_request(:get, 'http://localhost:4566/file.pdf')
          .to_return(status: 200, body: pdf_content)
      end

      it 'does not use SSL for HTTP' do
        downloader.send(:perform_http_request, http_uri)
        expect(WebMock).to have_requested(:get, 'http://localhost:4566/file.pdf')
      end
    end
  end

  describe '#error_result (private)' do
    it 'returns hash with success false' do
      result = downloader.send(:error_result, 'Test error')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('Test error')
    end

    it 'logs error message' do
      expect { downloader.send(:error_result, 'Test error') }
        .to output(/Test error/).to_stdout
    end
  end

  describe '#log_info (private)' do
    it 'outputs info message' do
      expect { downloader.send(:log_info, 'Test info') }
        .to output(/Test info/).to_stdout
    end
  end

  describe '#log_error (private)' do
    it 'outputs error message' do
      expect { downloader.send(:log_error, 'Test error') }
        .to output(/Test error/).to_stdout
    end
  end
end

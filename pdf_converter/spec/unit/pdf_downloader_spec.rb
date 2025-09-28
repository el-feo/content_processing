# frozen_string_literal: true

require 'spec_helper'
require_relative '../../pdf_downloader'
require 'webmock/rspec'

RSpec.describe PdfDownloader do
  let(:valid_s3_url) { 'https://s3.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }
  let(:invalid_url) { 'not-a-url' }
  let(:pdf_content) { "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n>>\nendobj\nxref\n0 1\n0000000000 65535 f \ntrailer\n<<\n/Size 1\n/Root 1 0 R\n>>\nstartxref\n9\n%%EOF" }

  before do
    WebMock.disable_net_connect!
  end

  after do
    WebMock.reset!
  end

  describe '#initialize' do
    it 'creates a new PdfDownloader instance' do
      downloader = described_class.new
      expect(downloader).to be_a(PdfDownloader)
    end
  end

  describe '#download' do
    context 'with valid S3 signed URL' do
      before do
        stub_request(:get, valid_s3_url)
          .to_return(status: 200, body: pdf_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'downloads PDF content successfully' do
        downloader = described_class.new
        result = downloader.download(valid_s3_url)

        expect(result[:success]).to be true
        expect(result[:content]).to eq(pdf_content)
        expect(result[:content_type]).to eq('application/pdf')
      end

      it 'validates PDF content format' do
        downloader = described_class.new
        result = downloader.download(valid_s3_url)

        expect(result[:content]).to start_with('%PDF-')
      end
    end

    context 'with invalid URL' do
      it 'returns error for malformed URL' do
        downloader = described_class.new
        result = downloader.download(invalid_url)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid URL')
      end
    end

    context 'with network errors' do
      before do
        stub_request(:get, valid_s3_url).to_timeout
      end

      it 'handles timeout errors' do
        downloader = described_class.new
        result = downloader.download(valid_s3_url)

        expect(result[:success]).to be false
        expect(result[:error]).to include('timeout')
      end
    end

    context 'with HTTP errors' do
      before do
        stub_request(:get, valid_s3_url)
          .to_return(status: 404, body: 'Not Found')
      end

      it 'handles 404 errors' do
        downloader = described_class.new
        result = downloader.download(valid_s3_url)

        expect(result[:success]).to be false
        expect(result[:error]).to include('404')
      end
    end

    context 'with non-PDF content' do
      before do
        stub_request(:get, valid_s3_url)
          .to_return(status: 200, body: 'Not a PDF', headers: { 'Content-Type' => 'text/plain' })
      end

      it 'rejects non-PDF content' do
        downloader = described_class.new
        result = downloader.download(valid_s3_url)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid PDF')
      end
    end

    context 'with large files' do
      let(:large_pdf_content) { "%PDF-1.4\n" + "x" * (10 * 1024 * 1024) + "\n%%EOF" } # 10MB+ content

      before do
        stub_request(:get, valid_s3_url)
          .to_return(status: 200, body: large_pdf_content, headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'handles large files within memory constraints' do
        downloader = described_class.new
        result = downloader.download(valid_s3_url)

        expect(result[:success]).to be true
        expect(result[:content].length).to be > (10 * 1024 * 1024)
      end
    end
  end

  describe '#validate_pdf_content' do
    it 'accepts valid PDF content' do
      downloader = described_class.new
      expect(downloader.validate_pdf_content(pdf_content)).to be true
    end

    it 'rejects non-PDF content' do
      downloader = described_class.new
      expect(downloader.validate_pdf_content('Not a PDF')).to be false
    end

    it 'rejects empty content' do
      downloader = described_class.new
      expect(downloader.validate_pdf_content('')).to be false
    end
  end
end
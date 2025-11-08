# frozen_string_literal: true

require 'spec_helper'
require_relative '../../app/url_validator'

RSpec.describe UrlValidator do
  let(:validator) { described_class.new }
  let(:s3_url_parser) { class_double(S3UrlParser).as_null_object }

  before do
    stub_const('S3UrlParser', s3_url_parser)
  end

  describe 'REQUIRED_S3_SIGNATURE_PARAMS' do
    it 'includes X-Amz-Algorithm' do
      expect(described_class::REQUIRED_S3_SIGNATURE_PARAMS).to include('X-Amz-Algorithm')
    end

    it 'is frozen' do
      expect(described_class::REQUIRED_S3_SIGNATURE_PARAMS).to be_frozen
    end
  end

  describe 'PDF_EXTENSIONS' do
    it 'includes .pdf extension' do
      expect(described_class::PDF_EXTENSIONS).to include('.pdf')
    end

    it 'is frozen' do
      expect(described_class::PDF_EXTENSIONS).to be_frozen
    end
  end

  describe '#valid_s3_destination_url?' do
    context 'with valid S3 destination URL' do
      let(:url) { 'https://bucket.s3.amazonaws.com/output/?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'returns true' do
        expect(validator.valid_s3_destination_url?(url)).to be true
      end
    end

    context 'with valid S3 destination URL without PDF extension' do
      let(:url) { 'https://bucket.s3.amazonaws.com/output/images/?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'returns true without requiring PDF extension' do
        expect(validator.valid_s3_destination_url?(url)).to be true
      end
    end

    context 'with nil URL' do
      it 'returns false' do
        expect(validator.valid_s3_destination_url?(nil)).to be false
      end
    end

    context 'with empty URL' do
      it 'returns false' do
        expect(validator.valid_s3_destination_url?('')).to be false
      end
    end

    context 'with URL missing signature params' do
      let(:url) { 'https://bucket.s3.amazonaws.com/output/' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'returns false' do
        expect(validator.valid_s3_destination_url?(url)).to be false
      end
    end
  end

  describe '#valid_s3_signed_url?' do
    context 'with valid S3 signed URL for PDF' do
      let(:url) { 'https://bucket.s3.amazonaws.com/input.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'returns true' do
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end

    context 'with valid URL but not PDF extension' do
      let(:url) { 'https://bucket.s3.amazonaws.com/file.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'returns false when PDF extension required' do
        expect(validator.valid_s3_signed_url?(url)).to be false
      end
    end

    context 'with uppercase PDF extension' do
      let(:url) { 'https://bucket.s3.amazonaws.com/input.PDF?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'returns true with case-insensitive check' do
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end

    context 'with nil URL' do
      it 'returns false' do
        expect(validator.valid_s3_signed_url?(nil)).to be false
      end
    end

    context 'with empty URL' do
      it 'returns false' do
        expect(validator.valid_s3_signed_url?('')).to be false
      end
    end

    context 'with invalid URI syntax' do
      let(:url) { 'not a valid uri :///' }

      it 'returns false' do
        expect(validator.valid_s3_signed_url?(url)).to be false
      end
    end
  end

  describe '#valid_url?' do
    context 'with valid HTTPS URL' do
      it 'returns true' do
        expect(validator.valid_url?('https://example.com/webhook')).to be true
      end
    end

    context 'with valid HTTP URL' do
      it 'returns true' do
        expect(validator.valid_url?('http://localhost:3000/webhook')).to be true
      end
    end

    context 'with FTP URL' do
      it 'returns false for non-HTTP(S) schemes' do
        expect(validator.valid_url?('ftp://example.com/file')).to be false
      end
    end

    context 'with nil URL' do
      it 'returns false' do
        expect(validator.valid_url?(nil)).to be false
      end
    end

    context 'with empty URL' do
      it 'returns false' do
        expect(validator.valid_url?('')).to be false
      end
    end

    context 'with invalid URI syntax' do
      it 'returns false' do
        expect(validator.valid_url?('not a valid uri')).to be false
      end
    end

    context 'with malformed URL' do
      it 'returns false' do
        expect(validator.valid_url?('ht!tp://invalid')).to be false
      end
    end
  end

  describe '#extract_s3_info' do
    context 'with valid S3 signed URL' do
      let(:url) { 'https://bucket.s3.amazonaws.com/key.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }
      let(:s3_info) { { bucket: 'bucket', key: 'key.pdf', region: 'us-east-1' } }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
        allow(s3_url_parser).to receive(:extract_s3_info).with(url).and_return(s3_info)
      end

      it 'returns S3 info hash' do
        result = validator.extract_s3_info(url)
        expect(result).to eq(s3_info)
      end

      it 'calls S3UrlParser.extract_s3_info' do
        validator.extract_s3_info(url)
        expect(s3_url_parser).to have_received(:extract_s3_info).with(url)
      end
    end

    context 'with invalid S3 URL' do
      let(:url) { 'https://example.com/not-s3' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).and_return(false)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'returns nil' do
        expect(validator.extract_s3_info(url)).to be_nil
      end

      it 'does not call S3UrlParser.extract_s3_info' do
        validator.extract_s3_info(url)
        expect(s3_url_parser).not_to have_received(:extract_s3_info)
      end
    end
  end

  describe '#validate_s3_url (private)' do
    context 'scheme validation' do
      context 'with HTTPS scheme' do
        let(:url) { 'https://bucket.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
          allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
        end

        it 'accepts HTTPS scheme' do
          expect(validator.valid_s3_signed_url?(url)).to be true
        end
      end

      context 'with HTTP scheme for LocalStack' do
        let(:url) { 'http://localhost:4566/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).and_return(false)
          allow(s3_url_parser).to receive(:localstack_hostname?).with('localhost').and_return(true)
        end

        it 'accepts HTTP for LocalStack hostname' do
          expect(validator.valid_s3_signed_url?(url)).to be true
        end
      end

      context 'with HTTP scheme for non-LocalStack' do
        let(:url) { 'http://bucket.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
          allow(s3_url_parser).to receive(:localstack_hostname?).with('bucket.s3.amazonaws.com').and_return(false)
        end

        it 'rejects HTTP for non-LocalStack' do
          expect(validator.valid_s3_signed_url?(url)).to be false
        end
      end
    end

    context 'hostname validation' do
      context 'with S3 hostname' do
        let(:url) { 'https://bucket.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
          allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
        end

        it 'accepts S3 hostname' do
          expect(validator.valid_s3_signed_url?(url)).to be true
        end
      end

      context 'with LocalStack hostname' do
        let(:url) { 'http://localhost:4566/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).and_return(false)
          allow(s3_url_parser).to receive(:localstack_hostname?).with('localhost').and_return(true)
        end

        it 'accepts LocalStack hostname' do
          expect(validator.valid_s3_signed_url?(url)).to be true
        end
      end

      context 'with non-S3 hostname' do
        let(:url) { 'https://example.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).with('example.com').and_return(false)
          allow(s3_url_parser).to receive(:localstack_hostname?).with('example.com').and_return(false)
        end

        it 'rejects non-S3 hostname' do
          expect(validator.valid_s3_signed_url?(url)).to be false
        end
      end
    end

    context 'PDF file validation' do
      context 'with PDF extension in path' do
        let(:url) { 'https://bucket.s3.amazonaws.com/dir/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
          allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
        end

        it 'accepts URL with PDF extension' do
          expect(validator.valid_s3_signed_url?(url)).to be true
        end
      end

      context 'with nil path' do
        # This is actually hard to test directly because URI.parse will handle paths
        # but we can test the pdf_file? method indirectly through validation
        let(:url) { 'https://bucket.s3.amazonaws.com?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
          allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
        end

        it 'rejects URL without file path when PDF required' do
          expect(validator.valid_s3_signed_url?(url)).to be false
        end
      end
    end

    context 'signature parameter validation' do
      context 'with all required signature parameters' do
        let(:url) { 'https://bucket.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=test' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
          allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
        end

        it 'accepts URL with signature parameters' do
          expect(validator.valid_s3_signed_url?(url)).to be true
        end
      end

      context 'with nil query string' do
        let(:url) { 'https://bucket.s3.amazonaws.com/file.pdf' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
          allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
        end

        it 'rejects URL without query parameters' do
          expect(validator.valid_s3_signed_url?(url)).to be false
        end
      end

      context 'with empty query string' do
        let(:url) { 'https://bucket.s3.amazonaws.com/file.pdf?' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
          allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
        end

        it 'rejects URL with empty query string' do
          expect(validator.valid_s3_signed_url?(url)).to be false
        end
      end

      context 'with query params but missing required signature' do
        let(:url) { 'https://bucket.s3.amazonaws.com/file.pdf?foo=bar&baz=qux' }

        before do
          allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
          allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
        end

        it 'rejects URL without X-Amz-Algorithm' do
          expect(validator.valid_s3_signed_url?(url)).to be false
        end
      end
    end
  end

  describe '#valid_scheme? (private)' do
    # Tested indirectly through validate_s3_url tests above
    # Additional direct tests for edge cases

    context 'with http scheme and LocalStack' do
      let(:url) { 'http://localhost:4566/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).and_return(false)
        allow(s3_url_parser).to receive(:localstack_hostname?).with('localhost').and_return(true)
      end

      it 'validates through full URL validation' do
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end

    context 'with https scheme' do
      let(:url) { 'https://bucket.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'validates through full URL validation' do
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end
  end

  describe '#valid_s3_host? (private)' do
    # Tested indirectly through validate_s3_url tests
    # Tests verify both S3 and LocalStack hostname acceptance

    context 'with S3 hostname' do
      let(:url) { 'https://bucket.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'validates S3 hostname through full URL validation' do
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end

    context 'with LocalStack hostname' do
      let(:url) { 'http://localhost:4566/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).and_return(false)
        allow(s3_url_parser).to receive(:localstack_hostname?).with('localhost').and_return(true)
      end

      it 'validates LocalStack hostname through full URL validation' do
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end
  end

  describe '#pdf_file? (private)' do
    # Tested indirectly through validate_s3_url tests
    # Additional coverage for edge cases

    context 'with .pdf extension' do
      let(:url) { 'https://bucket.s3.amazonaws.com/document.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'accepts PDF files' do
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end

    context 'with mixed case .PDF extension' do
      let(:url) { 'https://bucket.s3.amazonaws.com/document.PdF?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'accepts case-insensitive PDF extension' do
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end

    context 'with non-PDF extension' do
      let(:url) { 'https://bucket.s3.amazonaws.com/document.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'rejects non-PDF files when PDF required' do
        expect(validator.valid_s3_signed_url?(url)).to be false
      end
    end
  end

  describe '#s3_signature_params? (private)' do
    # Tested indirectly through validate_s3_url tests
    # These tests verify the signature parameter validation logic

    context 'with valid signature parameters' do
      let(:url) { 'https://bucket.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'accepts URLs with required signature params' do
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end

    context 'with additional query parameters' do
      let(:url) { 'https://bucket.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=test&foo=bar' }

      before do
        allow(s3_url_parser).to receive(:s3_hostname?).with('bucket.s3.amazonaws.com').and_return(true)
        allow(s3_url_parser).to receive(:localstack_hostname?).and_return(false)
      end

      it 'accepts URLs with additional parameters' do
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end
  end

  describe '#log_debug (private)' do
    # This method is conditional and doesn't affect behavior
    # It's tested implicitly but we ensure it doesn't raise errors

    context 'when logger is not defined' do
      it 'does not raise error when calling validation methods' do
        expect { validator.valid_url?('https://example.com') }.not_to raise_error
      end
    end
  end
end

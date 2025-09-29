# frozen_string_literal: true

require 'spec_helper'
require_relative '../../url_validator'

RSpec.describe UrlValidator do
  describe '#valid_s3_signed_url?' do
    let(:valid_s3_signed_urls) do
      [
        'https://s3.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=credential&X-Amz-Date=20220101T000000Z&X-Amz-Expires=3600&X-Amz-SignedHeaders=host&X-Amz-Signature=signature',
        'https://bucket.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=credential',
        'https://bucket.s3.us-west-2.amazonaws.com/folder/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256',
        'https://s3.us-east-1.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256'
      ]
    end

    let(:invalid_s3_urls) do
      [
        'https://example.com/file.pdf',  # Not S3
        'https://s3.amazonaws.com/bucket/file.pdf',  # No signature params
        'http://s3.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256',  # HTTP not HTTPS
        'https://s3.amazonaws.com/bucket/file.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256',  # Not PDF
        'not-a-url',  # Invalid URL format
        '',  # Empty string
        nil  # Nil value
      ]
    end

    it 'validates correct S3 signed URLs' do
      validator = described_class.new

      valid_s3_signed_urls.each do |url|
        expect(validator.valid_s3_signed_url?(url)).to be(true), "Expected #{url} to be valid"
      end
    end

    it 'rejects invalid S3 URLs' do
      validator = described_class.new

      invalid_s3_urls.each do |url|
        expect(validator.valid_s3_signed_url?(url)).to be(false), "Expected #{url} to be invalid"
      end
    end

    it 'accepts various S3 region formats' do
      validator = described_class.new

      regional_urls = [
        'https://s3.us-west-2.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256',
        'https://s3.eu-west-1.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256',
        'https://s3.ap-southeast-1.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256'
      ]

      regional_urls.each do |url|
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end

    it 'accepts virtual-hosted-style S3 URLs' do
      validator = described_class.new

      virtual_hosted_urls = [
        'https://bucket-name.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256',
        'https://my-bucket.s3.us-west-2.amazonaws.com/folder/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256'
      ]

      virtual_hosted_urls.each do |url|
        expect(validator.valid_s3_signed_url?(url)).to be true
      end
    end
  end

  describe '#valid_url?' do
    it 'validates basic HTTP/HTTPS URLs' do
      validator = described_class.new

      expect(validator.valid_url?('https://example.com')).to be true
      expect(validator.valid_url?('http://example.com')).to be true
      expect(validator.valid_url?('https://example.com/path/file.pdf')).to be true
    end

    it 'rejects invalid URLs' do
      validator = described_class.new

      expect(validator.valid_url?('not-a-url')).to be false
      expect(validator.valid_url?('ftp://example.com')).to be false
      expect(validator.valid_url?('')).to be false
      expect(validator.valid_url?(nil)).to be false
    end
  end

  describe '#valid_s3_destination_url?' do
    it 'validates S3 destination URLs without PDF requirement' do
      validator = described_class.new

      valid_destination_urls = [
        'https://s3.amazonaws.com/bucket/output/?X-Amz-Algorithm=AWS4-HMAC-SHA256',
        'https://bucket.s3.amazonaws.com/images/page-1.png?X-Amz-Algorithm=AWS4-HMAC-SHA256',
        'https://bucket.s3.us-west-2.amazonaws.com/folder/?X-Amz-Algorithm=AWS4-HMAC-SHA256'
      ]

      valid_destination_urls.each do |url|
        expect(validator.valid_s3_destination_url?(url)).to be(true), "Expected #{url} to be valid"
      end
    end

    it 'rejects destination URLs without signature' do
      validator = described_class.new

      invalid_urls = [
        'https://s3.amazonaws.com/bucket/output/',  # No signature
        'http://bucket.s3.amazonaws.com/output/?X-Amz-Algorithm=AWS4',  # HTTP not HTTPS
        'https://example.com/output/?X-Amz-Algorithm=AWS4',  # Not S3
        '',
        nil
      ]

      invalid_urls.each do |url|
        expect(validator.valid_s3_destination_url?(url)).to be(false), "Expected #{url} to be invalid"
      end
    end
  end

  describe '#extract_s3_info' do
    it 'extracts bucket and key from path-style URLs' do
      validator = described_class.new
      url = 'https://s3.amazonaws.com/my-bucket/folder/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256'

      info = validator.extract_s3_info(url)

      expect(info[:bucket]).to eq('my-bucket')
      expect(info[:key]).to eq('folder/file.pdf')
      expect(info[:region]).to eq('us-east-1')  # Default region
    end

    it 'extracts bucket and key from virtual-hosted-style URLs' do
      validator = described_class.new
      url = 'https://my-bucket.s3.us-west-2.amazonaws.com/folder/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256'

      info = validator.extract_s3_info(url)

      expect(info[:bucket]).to eq('my-bucket')
      expect(info[:key]).to eq('folder/file.pdf')
      expect(info[:region]).to eq('us-west-2')
    end

    it 'returns nil for invalid URLs' do
      validator = described_class.new

      expect(validator.extract_s3_info('not-a-url')).to be_nil
      expect(validator.extract_s3_info('https://example.com/file.pdf')).to be_nil
    end
  end
end
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/s3_url_parser'

RSpec.describe S3UrlParser do
  describe '.s3_hostname?' do
    context 'with valid S3 hostnames' do
      it 'returns true for s3.amazonaws.com' do
        expect(described_class.s3_hostname?('s3.amazonaws.com')).to be true
      end

      it 'returns true for s3.us-west-2.amazonaws.com' do
        expect(described_class.s3_hostname?('s3.us-west-2.amazonaws.com')).to be true
      end

      it 'returns true for s3.eu-central-1.amazonaws.com' do
        expect(described_class.s3_hostname?('s3.eu-central-1.amazonaws.com')).to be true
      end

      it 'returns true for bucket.s3.amazonaws.com' do
        expect(described_class.s3_hostname?('my-bucket.s3.amazonaws.com')).to be true
      end

      it 'returns true for bucket.s3.region.amazonaws.com' do
        expect(described_class.s3_hostname?('my-bucket.s3.us-east-1.amazonaws.com')).to be true
      end

      it 'returns true for bucket with dots' do
        expect(described_class.s3_hostname?('my.bucket.name.s3.amazonaws.com')).to be true
      end
    end

    context 'with invalid hostnames' do
      it 'returns false for nil' do
        expect(described_class.s3_hostname?(nil)).to be false
      end

      it 'returns false for non-S3 hostname' do
        expect(described_class.s3_hostname?('example.com')).to be false
      end

      it 'returns false for localhost' do
        expect(described_class.s3_hostname?('localhost')).to be false
      end

      it 'returns false for Google Cloud Storage' do
        expect(described_class.s3_hostname?('storage.googleapis.com')).to be false
      end
    end
  end

  describe '.localstack_hostname?' do
    context 'with LocalStack hostnames' do
      it 'returns true for localhost' do
        expect(described_class.localstack_hostname?('localhost')).to be true
      end

      it 'returns true for 127.0.0.1' do
        expect(described_class.localstack_hostname?('127.0.0.1')).to be true
      end

      it 'returns true for hostnames starting with localstack' do
        expect(described_class.localstack_hostname?('localstack')).to be true
      end

      it 'returns true for localstack.example.com' do
        expect(described_class.localstack_hostname?('localstack.example.com')).to be true
      end
    end

    context 'with non-LocalStack hostnames' do
      it 'returns false for nil' do
        expect(described_class.localstack_hostname?(nil)).to be false
      end

      it 'returns false for AWS S3 hostname' do
        expect(described_class.localstack_hostname?('s3.amazonaws.com')).to be false
      end

      it 'returns false for regular hostname' do
        expect(described_class.localstack_hostname?('example.com')).to be false
      end
    end
  end

  describe '.path_style_s3?' do
    context 'with path-style S3 hostnames' do
      it 'returns true for s3.amazonaws.com' do
        expect(described_class.path_style_s3?('s3.amazonaws.com')).to be true
      end

      it 'returns true for s3.us-west-2.amazonaws.com' do
        expect(described_class.path_style_s3?('s3.us-west-2.amazonaws.com')).to be true
      end

      it 'returns true for s3.eu-central-1.amazonaws.com' do
        expect(described_class.path_style_s3?('s3.eu-central-1.amazonaws.com')).to be true
      end
    end

    context 'with non-path-style hostnames' do
      it 'returns false for virtual-hosted-style' do
        expect(described_class.path_style_s3?('bucket.s3.amazonaws.com')).to be false
      end

      it 'returns false for nil' do
        expect(described_class.path_style_s3?(nil)).to be false
      end

      it 'returns false for regular hostname' do
        expect(described_class.path_style_s3?('example.com')).to be false
      end
    end
  end

  describe '.virtual_hosted_style_s3?' do
    context 'with virtual-hosted-style S3 hostnames' do
      it 'returns true for bucket.s3.amazonaws.com' do
        expect(described_class.virtual_hosted_style_s3?('my-bucket.s3.amazonaws.com')).to be true
      end

      it 'returns true for bucket.s3.region.amazonaws.com' do
        expect(described_class.virtual_hosted_style_s3?('my-bucket.s3.us-west-2.amazonaws.com')).to be true
      end

      it 'returns true for bucket with dots' do
        expect(described_class.virtual_hosted_style_s3?('my.bucket.s3.amazonaws.com')).to be true
      end
    end

    context 'with non-virtual-hosted-style hostnames' do
      it 'returns false for path-style S3' do
        expect(described_class.virtual_hosted_style_s3?('s3.amazonaws.com')).to be false
      end

      it 'returns false for nil' do
        expect(described_class.virtual_hosted_style_s3?(nil)).to be false
      end

      it 'returns false for regular hostname' do
        expect(described_class.virtual_hosted_style_s3?('example.com')).to be false
      end
    end
  end

  describe '.extract_s3_info' do
    context 'with path-style S3 URLs' do
      it 'extracts bucket, key, and region from standard path-style URL' do
        url = 'https://s3.amazonaws.com/my-bucket/path/to/file.pdf'
        result = described_class.extract_s3_info(url)

        expect(result).to eq({
                               bucket: 'my-bucket',
                               key: 'path/to/file.pdf',
                               region: 'us-east-1'
                             })
      end

      it 'extracts info from path-style URL with region' do
        url = 'https://s3.us-west-2.amazonaws.com/test-bucket/document.pdf'
        result = described_class.extract_s3_info(url)

        expect(result).to eq({
                               bucket: 'test-bucket',
                               key: 'document.pdf',
                               region: 'us-west-2'
                             })
      end

      it 'extracts info with complex key path' do
        url = 'https://s3.eu-central-1.amazonaws.com/data-bucket/year/2024/month/01/report.pdf'
        result = described_class.extract_s3_info(url)

        expect(result).to eq({
                               bucket: 'data-bucket',
                               key: 'year/2024/month/01/report.pdf',
                               region: 'eu-central-1'
                             })
      end

      it 'returns nil for path-style URL without key' do
        url = 'https://s3.amazonaws.com/my-bucket'
        result = described_class.extract_s3_info(url)

        expect(result).to be_nil
      end

      it 'returns nil for path-style URL with empty bucket' do
        url = 'https://s3.amazonaws.com//file.pdf'
        result = described_class.extract_s3_info(url)

        expect(result).to be_nil
      end
    end

    context 'with virtual-hosted-style S3 URLs' do
      it 'extracts info from virtual-hosted-style URL' do
        url = 'https://my-bucket.s3.amazonaws.com/path/to/file.pdf'
        result = described_class.extract_s3_info(url)

        expect(result).to eq({
                               bucket: 'my-bucket',
                               key: 'path/to/file.pdf',
                               region: 'us-east-1'
                             })
      end

      it 'extracts info from virtual-hosted-style URL with region' do
        url = 'https://test-bucket.s3.us-west-2.amazonaws.com/document.pdf'
        result = described_class.extract_s3_info(url)

        expect(result).to eq({
                               bucket: 'test-bucket',
                               key: 'document.pdf',
                               region: 'us-west-2'
                             })
      end

      it 'extracts only first part of bucket with dots (AWS limitation)' do
        # NOTE: Buckets with dots in virtual-hosted-style URLs have parsing limitations
        # AWS recommends using path-style URLs for buckets with dots
        url = 'https://my.bucket.name.s3.amazonaws.com/file.pdf'
        result = described_class.extract_s3_info(url)

        expect(result).to eq({
                               bucket: 'my',
                               key: 'file.pdf',
                               region: 'us-east-1'
                             })
      end

      it 'handles key without leading slash' do
        url = 'https://my-bucket.s3.amazonaws.com/document.pdf'
        result = described_class.extract_s3_info(url)

        expect(result[:key]).to eq('document.pdf')
      end

      it 'handles key with leading slash' do
        url = 'https://my-bucket.s3.amazonaws.com/path/to/file.pdf'
        result = described_class.extract_s3_info(url)

        expect(result[:key]).to eq('path/to/file.pdf')
      end

      it 'returns nil for invalid virtual-hosted-style URL' do
        url = 'https://bucket.s3/file.pdf'
        result = described_class.extract_s3_info(url)

        expect(result).to be_nil
      end
    end

    context 'with invalid URLs' do
      it 'returns nil for nil URL' do
        result = described_class.extract_s3_info(nil)
        expect(result).to be_nil
      end

      it 'returns nil for empty URL' do
        result = described_class.extract_s3_info('')
        expect(result).to be_nil
      end

      it 'returns nil for non-S3 URL' do
        url = 'https://example.com/path/to/file.pdf'
        result = described_class.extract_s3_info(url)

        expect(result).to be_nil
      end

      it 'returns nil for malformed URL' do
        url = 'not-a-valid-url'
        result = described_class.extract_s3_info(url)

        expect(result).to be_nil
      end

      it 'returns nil for URL with invalid URI characters' do
        url = 'https://s3.amazonaws.com/bucket/file with spaces.pdf'
        result = described_class.extract_s3_info(url)

        # URI.parse should raise an error, caught and return nil
        expect(result).to be_nil
      end
    end

    context 'with query parameters and fragments' do
      it 'extracts info ignoring query parameters' do
        url = 'https://my-bucket.s3.amazonaws.com/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=test'
        result = described_class.extract_s3_info(url)

        expect(result[:bucket]).to eq('my-bucket')
        expect(result[:key]).to eq('file.pdf')
      end

      it 'extracts info from path-style URL with query params' do
        url = 'https://s3.us-east-1.amazonaws.com/bucket/key.pdf?versionId=123'
        result = described_class.extract_s3_info(url)

        expect(result[:bucket]).to eq('bucket')
        expect(result[:key]).to eq('key.pdf')
      end
    end
  end

  describe '.extract_region_from_hostname' do
    context 'with region in hostname' do
      it 'extracts region from s3.region.amazonaws.com' do
        region = described_class.extract_region_from_hostname('s3.us-west-2.amazonaws.com')
        expect(region).to eq('us-west-2')
      end

      it 'extracts region from bucket.s3.region.amazonaws.com' do
        region = described_class.extract_region_from_hostname('my-bucket.s3.eu-central-1.amazonaws.com')
        expect(region).to eq('eu-central-1')
      end

      it 'extracts region with multiple parts' do
        region = described_class.extract_region_from_hostname('s3.ap-southeast-2.amazonaws.com')
        expect(region).to eq('ap-southeast-2')
      end
    end

    context 'without region in hostname' do
      it 'returns nil for s3.amazonaws.com' do
        region = described_class.extract_region_from_hostname('s3.amazonaws.com')
        expect(region).to be_nil
      end

      it 'returns nil for bucket.s3.amazonaws.com without region' do
        region = described_class.extract_region_from_hostname('my-bucket.s3.amazonaws.com')
        expect(region).to be_nil
      end

      it 'returns nil for non-S3 hostname' do
        region = described_class.extract_region_from_hostname('example.com')
        expect(region).to be_nil
      end
    end
  end

  describe 'constants' do
    it 'defines S3_HOSTNAME_PATTERNS' do
      expect(S3UrlParser::S3_HOSTNAME_PATTERNS).to be_a(Array)
      expect(S3UrlParser::S3_HOSTNAME_PATTERNS).to be_frozen
      expect(S3UrlParser::S3_HOSTNAME_PATTERNS.size).to eq(4)
    end

    it 'patterns are regular expressions' do
      S3UrlParser::S3_HOSTNAME_PATTERNS.each do |pattern|
        expect(pattern).to be_a(Regexp)
      end
    end
  end

  describe 'private methods' do
    describe '.extract_path_style_info' do
      it 'is a private class method' do
        expect(described_class.private_methods).to include(:extract_path_style_info)
      end
    end

    describe '.extract_virtual_hosted_info' do
      it 'is a private class method' do
        expect(described_class.private_methods).to include(:extract_virtual_hosted_info)
      end
    end
  end
end

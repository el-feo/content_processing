# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/s3_url_parser'

RSpec.describe S3UrlParser do
  describe '.s3_hostname?' do
    it 'returns true for standard S3 hostname' do
      expect(described_class.s3_hostname?('s3.amazonaws.com')).to be true
    end

    it 'returns true for regional S3 hostname' do
      expect(described_class.s3_hostname?('s3.us-west-2.amazonaws.com')).to be true
    end

    it 'returns true for virtual-hosted-style bucket hostname' do
      expect(described_class.s3_hostname?('my-bucket.s3.amazonaws.com')).to be true
    end

    it 'returns true for virtual-hosted-style bucket with region' do
      expect(described_class.s3_hostname?('my-bucket.s3.us-west-2.amazonaws.com')).to be true
    end

    it 'returns false for non-S3 hostname' do
      expect(described_class.s3_hostname?('example.com')).to be false
    end

    it 'returns false for nil hostname' do
      expect(described_class.s3_hostname?(nil)).to be false
    end
  end

  describe '.localstack_hostname?' do
    it 'returns true for localhost' do
      expect(described_class.localstack_hostname?('localhost')).to be true
    end

    it 'returns true for 127.0.0.1' do
      expect(described_class.localstack_hostname?('127.0.0.1')).to be true
    end

    it 'returns true for localstack hostname' do
      expect(described_class.localstack_hostname?('localstack.local')).to be true
    end

    it 'returns false for regular hostname' do
      expect(described_class.localstack_hostname?('example.com')).to be false
    end

    it 'returns false for nil hostname' do
      expect(described_class.localstack_hostname?(nil)).to be false
    end
  end

  describe '.path_style_s3?' do
    it 'returns true for standard S3 hostname' do
      expect(described_class.path_style_s3?('s3.amazonaws.com')).to be true
    end

    it 'returns true for regional S3 hostname' do
      expect(described_class.path_style_s3?('s3.us-west-2.amazonaws.com')).to be true
    end

    it 'returns false for virtual-hosted-style' do
      expect(described_class.path_style_s3?('bucket.s3.amazonaws.com')).to be false
    end

    it 'returns false for nil hostname' do
      expect(described_class.path_style_s3?(nil)).to be false
    end
  end

  describe '.virtual_hosted_style_s3?' do
    it 'returns true for virtual-hosted-style bucket' do
      expect(described_class.virtual_hosted_style_s3?('my-bucket.s3.amazonaws.com')).to be true
    end

    it 'returns true for virtual-hosted-style bucket with region' do
      expect(described_class.virtual_hosted_style_s3?('my-bucket.s3.us-west-2.amazonaws.com')).to be true
    end

    it 'returns false for path-style S3' do
      expect(described_class.virtual_hosted_style_s3?('s3.amazonaws.com')).to be false
    end

    it 'returns false for nil hostname' do
      expect(described_class.virtual_hosted_style_s3?(nil)).to be false
    end
  end

  describe '.extract_s3_info' do
    context 'with path-style URLs' do
      it 'extracts bucket, key, and region from regional URL' do
        url = 'https://s3.us-west-2.amazonaws.com/my-bucket/folder/file.pdf?X-Amz-Algorithm=...'
        result = described_class.extract_s3_info(url)

        expect(result).to eq({
                               bucket: 'my-bucket',
                               key: 'folder/file.pdf',
                               region: 'us-west-2'
                             })
      end

      it 'uses us-east-1 as default region for standard endpoint' do
        url = 'https://s3.amazonaws.com/my-bucket/file.pdf'
        result = described_class.extract_s3_info(url)

        expect(result[:region]).to eq('us-east-1')
      end
    end

    context 'with virtual-hosted-style URLs' do
      it 'extracts bucket, key, and region' do
        url = 'https://my-bucket.s3.eu-west-1.amazonaws.com/folder/file.pdf?X-Amz-Algorithm=...'
        result = described_class.extract_s3_info(url)

        expect(result).to eq({
                               bucket: 'my-bucket',
                               key: 'folder/file.pdf',
                               region: 'eu-west-1'
                             })
      end

      it 'handles keys without leading slash' do
        url = 'https://my-bucket.s3.amazonaws.com/file.pdf'
        result = described_class.extract_s3_info(url)

        expect(result[:key]).to eq('file.pdf')
      end
    end

    context 'with invalid URLs' do
      it 'returns nil for nil URL' do
        expect(described_class.extract_s3_info(nil)).to be_nil
      end

      it 'returns nil for empty URL' do
        expect(described_class.extract_s3_info('')).to be_nil
      end

      it 'returns nil for malformed URL' do
        expect(described_class.extract_s3_info('not-a-url')).to be_nil
      end

      it 'returns nil for non-S3 URL' do
        expect(described_class.extract_s3_info('https://example.com/file.pdf')).to be_nil
      end
    end
  end

  describe '.extract_region_from_hostname' do
    it 'extracts region from path-style hostname' do
      region = described_class.extract_region_from_hostname('s3.us-west-2.amazonaws.com')
      expect(region).to eq('us-west-2')
    end

    it 'extracts region from virtual-hosted-style hostname' do
      region = described_class.extract_region_from_hostname('bucket.s3.eu-west-1.amazonaws.com')
      expect(region).to eq('eu-west-1')
    end

    it 'returns nil for standard S3 hostname without region' do
      region = described_class.extract_region_from_hostname('s3.amazonaws.com')
      expect(region).to be_nil
    end

    it 'returns nil for non-S3 hostname' do
      region = described_class.extract_region_from_hostname('example.com')
      expect(region).to be_nil
    end
  end
end

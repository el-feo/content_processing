# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/url_utils'

RSpec.describe UrlUtils do
  # Create a test class that includes the module to test instance methods
  let(:test_class) do
    Class.new do
      include UrlUtils
    end
  end
  let(:test_instance) { test_class.new }

  describe '#sanitize_url' do
    context 'with valid URLs' do
      it 'removes query parameters from URL' do
        url = 'https://example.com/path/to/file.pdf?key=secret&token=12345'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('https://example.com/path/to/file.pdf[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles URL without query parameters' do
        url = 'https://example.com/path/to/file.pdf'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('https://example.com/path/to/file.pdf[QUERY_PARAMS_HIDDEN]')
      end

      it 'sanitizes S3 presigned URL' do
        url = 'https://s3.amazonaws.com/bucket/key.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAEXAMPLE'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('https://s3.amazonaws.com/bucket/key.pdf[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles URL with fragment (fragments are not included)' do
        url = 'https://example.com/page#section?query=value'
        result = test_instance.sanitize_url(url)

        # Fragment is not included in URI output
        expect(result).to eq('https://example.com/page[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles URL with port (port is not included in output)' do
        url = 'https://example.com:8080/api/endpoint?api_key=secret'
        result = test_instance.sanitize_url(url)

        # Port is not included in URI output
        expect(result).to eq('https://example.com/api/endpoint[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles HTTP URLs' do
        url = 'http://example.com/file.pdf?token=abc123'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('http://example.com/file.pdf[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles URL with subdomain' do
        url = 'https://subdomain.example.com/path?secret=value'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('https://subdomain.example.com/path[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles URL with deep path' do
        url = 'https://example.com/a/b/c/d/e/file.pdf?param=value'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('https://example.com/a/b/c/d/e/file.pdf[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles root path' do
        url = 'https://example.com/?query=param'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('https://example.com/[QUERY_PARAMS_HIDDEN]')
      end
    end

    context 'with invalid or malformed URLs' do
      it 'returns error message for malformed URL' do
        url = 'not a valid url at all'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('[URL_PARSE_ERROR]')
      end

      it 'returns error message for URL with invalid characters' do
        url = 'https://example.com/path with spaces/file.pdf'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('[URL_PARSE_ERROR]')
      end

      it 'returns error message for nil' do
        result = test_instance.sanitize_url(nil)

        expect(result).to eq('[URL_PARSE_ERROR]')
      end

      it 'handles empty string as valid URI' do
        result = test_instance.sanitize_url('')

        # Empty string parses as a valid relative URI
        expect(result).to eq('://[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles URL with only scheme' do
        url = 'https://'
        result = test_instance.sanitize_url(url)

        # URL with only scheme parses but has nil host
        expect(result).to eq('https://[QUERY_PARAMS_HIDDEN]')
      end
    end

    context 'with edge cases' do
      it 'handles URL with multiple query parameters' do
        url = 'https://example.com/file?param1=value1&param2=value2&param3=value3'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('https://example.com/file[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles URL with encoded query parameters' do
        url = 'https://example.com/file?param=value%20with%20spaces'
        result = test_instance.sanitize_url(url)

        expect(result).to eq('https://example.com/file[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles localhost URL (port not included)' do
        url = 'http://localhost:3000/api/endpoint?token=secret'
        result = test_instance.sanitize_url(url)

        # Port is not included in output
        expect(result).to eq('http://localhost/api/endpoint[QUERY_PARAMS_HIDDEN]')
      end

      it 'handles IP address URL (port not included)' do
        url = 'http://127.0.0.1:4566/bucket/key?access_key=secret'
        result = test_instance.sanitize_url(url)

        # Port is not included in output
        expect(result).to eq('http://127.0.0.1/bucket/key[QUERY_PARAMS_HIDDEN]')
      end
    end
  end

  describe '.strip_query_params' do
    context 'with valid URLs' do
      it 'removes query parameters from single URL' do
        urls = ['https://example.com/file.pdf?key=secret']
        result = described_class.strip_query_params(urls)

        expect(result).to eq(['https://example.com/file.pdf'])
      end

      it 'removes query parameters from multiple URLs' do
        urls = [
          'https://example.com/file1.pdf?token=abc',
          'https://example.com/file2.pdf?token=def',
          'https://example.com/file3.pdf?token=ghi'
        ]
        result = described_class.strip_query_params(urls)

        expect(result).to eq([
                               'https://example.com/file1.pdf',
                               'https://example.com/file2.pdf',
                               'https://example.com/file3.pdf'
                             ])
      end

      it 'handles URLs without query parameters' do
        urls = ['https://example.com/file.pdf']
        result = described_class.strip_query_params(urls)

        expect(result).to eq(['https://example.com/file.pdf'])
      end

      it 'handles mix of URLs with and without query parameters' do
        urls = [
          'https://example.com/file1.pdf',
          'https://example.com/file2.pdf?token=abc',
          'https://example.com/file3.pdf'
        ]
        result = described_class.strip_query_params(urls)

        expect(result).to eq([
                               'https://example.com/file1.pdf',
                               'https://example.com/file2.pdf',
                               'https://example.com/file3.pdf'
                             ])
      end

      it 'preserves URL fragments' do
        urls = ['https://example.com/page#section?query=value']
        result = described_class.strip_query_params(urls)

        expect(result).to eq(['https://example.com/page#section'])
      end
    end

    context 'with empty or edge case inputs' do
      it 'returns empty array for empty input' do
        result = described_class.strip_query_params([])

        expect(result).to eq([])
      end

      it 'handles array with single empty string' do
        result = described_class.strip_query_params([''])

        # Empty string split by '?' returns [''], first element is '' which becomes nil in map
        expect(result).to eq([nil])
      end

      it 'handles URLs with only query parameters' do
        urls = ['?only=query']
        result = described_class.strip_query_params(urls)

        expect(result).to eq([''])
      end

      it 'handles URLs with multiple question marks' do
        urls = ['https://example.com/file?param1=value1?param2=value2']
        result = described_class.strip_query_params(urls)

        # Only splits on first '?'
        expect(result).to eq(['https://example.com/file'])
      end
    end

    context 'with S3 presigned URLs' do
      it 'strips presigned URL query parameters' do
        urls = [
          'https://s3.amazonaws.com/bucket/file.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAEXAMPLE'
        ]
        result = described_class.strip_query_params(urls)

        expect(result).to eq(['https://s3.amazonaws.com/bucket/file.pdf'])
      end

      it 'strips query params from multiple S3 URLs' do
        urls = [
          'https://s3.amazonaws.com/bucket1/key1.pdf?X-Amz-Signature=abc',
          'https://my-bucket.s3.amazonaws.com/key2.pdf?X-Amz-Expires=3600'
        ]
        result = described_class.strip_query_params(urls)

        expect(result).to eq([
                               'https://s3.amazonaws.com/bucket1/key1.pdf',
                               'https://my-bucket.s3.amazonaws.com/key2.pdf'
                             ])
      end
    end
  end
end

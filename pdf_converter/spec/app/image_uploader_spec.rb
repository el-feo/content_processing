# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'tempfile'
require_relative '../../app/image_uploader'

RSpec.describe ImageUploader do
  let(:uploader) { described_class.new }
  let(:url) { 'https://s3.amazonaws.com/bucket/image.png?signed=true' }
  let(:content) { 'fake-png-content-binary-data' }

  before do
    WebMock.disable_net_connect!
  end

  after do
    WebMock.reset!
  end

  describe 'TIMEOUT_SECONDS' do
    it 'is set to 60 seconds' do
      expect(described_class::TIMEOUT_SECONDS).to eq(60)
    end
  end

  describe 'THREAD_POOL_SIZE' do
    it 'is set to 5' do
      expect(described_class::THREAD_POOL_SIZE).to eq(5)
    end
  end

  describe '#upload' do
    context 'with successful upload' do
      before do
        stub_request(:put, url)
          .to_return(status: 200, headers: { 'ETag' => '"test-etag-123"' })
      end

      it 'returns success with etag' do
        result = uploader.upload(url, content)
        expect(result[:success]).to be true
        expect(result[:etag]).to eq('"test-etag-123"')
      end

      it 'returns content size' do
        result = uploader.upload(url, content)
        expect(result[:size]).to eq(content.bytesize)
      end

      it 'logs upload info' do
        expect { uploader.upload(url, content) }
          .to output(/Starting image upload/).to_stdout
      end

      it 'logs success message' do
        expect { uploader.upload(url, content) }
          .to output(/Image upload completed successfully/).to_stdout
      end

      it 'sends PUT request with correct content type' do
        uploader.upload(url, content, 'image/jpeg')
        expect(WebMock).to have_requested(:put, url)
          .with(headers: { 'Content-Type' => 'image/jpeg' })
      end

      it 'sends PUT request with content length' do
        uploader.upload(url, content)
        expect(WebMock).to have_requested(:put, url)
          .with(headers: { 'Content-Length' => content.bytesize.to_s })
      end

      it 'sends content in request body' do
        uploader.upload(url, content)
        expect(WebMock).to have_requested(:put, url)
          .with(body: content)
      end
    end

    context 'with lowercase etag header' do
      before do
        stub_request(:put, url)
          .to_return(status: 200, headers: { 'etag' => '"lowercase-etag"' })
      end

      it 'accepts lowercase etag header' do
        result = uploader.upload(url, content)
        expect(result[:etag]).to eq('"lowercase-etag"')
      end
    end

    context 'with no etag header' do
      before do
        stub_request(:put, url)
          .to_return(status: 200, headers: {})
      end

      it 'returns no-etag when header missing' do
        result = uploader.upload(url, content)
        expect(result[:etag]).to eq('no-etag')
      end
    end

    context 'with custom content type' do
      before do
        stub_request(:put, url)
          .to_return(status: 200, headers: { 'ETag' => '"test-etag"' })
      end

      it 'uses custom content type' do
        uploader.upload(url, content, 'image/jpeg')
        expect(WebMock).to have_requested(:put, url)
          .with(headers: { 'Content-Type' => 'image/jpeg' })
      end
    end

    context 'with nil URL' do
      it 'returns error for nil URL' do
        result = uploader.upload(nil, content)
        expect(result[:success]).to be false
        expect(result[:error]).to include('URL cannot be nil or empty')
      end
    end

    context 'with empty URL' do
      it 'returns error for empty URL' do
        result = uploader.upload('', content)
        expect(result[:success]).to be false
        expect(result[:error]).to include('URL cannot be nil or empty')
      end
    end

    context 'with nil content' do
      it 'returns error for nil content' do
        result = uploader.upload(url, nil)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Content cannot be nil or empty')
      end
    end

    context 'with empty content' do
      it 'returns error for empty content' do
        result = uploader.upload(url, '')
        expect(result[:success]).to be false
        expect(result[:error]).to include('Content cannot be nil or empty')
      end
    end

    context 'with invalid URL format' do
      let(:invalid_url) { 'not a valid url' }

      it 'returns error for invalid URI' do
        result = uploader.upload(invalid_url, content)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid URL format')
      end
    end

    context 'with HTTP 403 error' do
      before do
        stub_request(:put, url)
          .to_return(status: 403, body: 'Forbidden')
      end

      it 'returns access denied error' do
        result = uploader.upload(url, content)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Access denied')
      end

      it 'mentions URL expiration' do
        result = uploader.upload(url, content)
        expect(result[:error]).to include('expired or invalid')
      end
    end

    context 'with HTTP 404 error' do
      before do
        stub_request(:put, url)
          .to_return(status: 404, body: 'Not Found')
      end

      it 'returns error for 404' do
        result = uploader.upload(url, content)
        expect(result[:success]).to be false
        expect(result[:error]).to include('HTTP 404')
      end
    end

    context 'with HTTP 500 error' do
      before do
        stub_request(:put, url)
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'returns error for 500' do
        result = uploader.upload(url, content)
        expect(result[:success]).to be false
        expect(result[:error]).to include('HTTP 500')
      end
    end

    context 'with network timeout' do
      before do
        stub_request(:put, url).to_timeout
      end

      it 'returns error for timeout' do
        result = uploader.upload(url, content)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Upload failed')
      end
    end

    context 'with redirect response' do
      before do
        stub_request(:put, url)
          .to_return(status: 301, headers: { 'Location' => 'https://new-location.com' })
      end

      it 'returns error for unexpected redirect' do
        result = uploader.upload(url, content)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Unexpected redirect')
      end
    end

    context 'with HTTP URL' do
      let(:http_url) { 'http://localhost:4566/bucket/image.png' }

      before do
        stub_request(:put, http_url)
          .to_return(status: 200, headers: { 'ETag' => '"test-etag"' })
      end

      it 'uploads to HTTP URL' do
        result = uploader.upload(http_url, content)
        expect(result[:success]).to be true
      end
    end

    context 'with HTTPS URL' do
      let(:https_url) { 'https://secure.example.com/image.png' }

      before do
        stub_request(:put, https_url)
          .to_return(status: 200, headers: { 'ETag' => '"test-etag"' })
      end

      it 'uploads to HTTPS URL with SSL' do
        result = uploader.upload(https_url, content)
        expect(result[:success]).to be true
      end
    end
  end

  describe '#upload_batch' do
    let(:urls) { ['https://s3.amazonaws.com/bucket/image-1.png?signed=true', 'https://s3.amazonaws.com/bucket/image-2.png?signed=true'] }
    let(:images) { %w[content-1 content-2] }

    context 'with successful batch upload' do
      before do
        stub_request(:put, urls[0])
          .to_return(status: 200, headers: { 'ETag' => '"etag-1"' })
        stub_request(:put, urls[1])
          .to_return(status: 200, headers: { 'ETag' => '"etag-2"' })
      end

      it 'uploads all images' do
        results = uploader.upload_batch(urls, images)
        expect(results.size).to eq(2)
        expect(results.all? { |r| r[:success] }).to be true
      end

      it 'maintains order of results' do
        results = uploader.upload_batch(urls, images)
        expect(results[0][:index]).to eq(0)
        expect(results[1][:index]).to eq(1)
      end

      it 'logs batch upload info' do
        expect { uploader.upload_batch(urls, images) }
          .to output(/Starting batch upload of 2 images/).to_stdout
      end

      it 'logs completion message' do
        expect { uploader.upload_batch(urls, images) }
          .to output(%r{Batch upload completed: 2/2 successful}).to_stdout
      end
    end

    context 'with mismatched URLs and images count' do
      let(:urls) { ['https://s3.amazonaws.com/bucket/image.png?signed=true'] }
      let(:images) { %w[content-1 content-2] }

      it 'raises ArgumentError' do
        expect { uploader.upload_batch(urls, images) }
          .to raise_error(ArgumentError, /Number of URLs must match/)
      end
    end

    context 'with some failed uploads' do
      before do
        stub_request(:put, urls[0])
          .to_return(status: 200, headers: { 'ETag' => '"etag-1"' })
        stub_request(:put, urls[1])
          .to_return(status: 403, body: 'Forbidden')
      end

      it 'returns mix of success and failure' do
        results = uploader.upload_batch(urls, images)
        expect(results[0][:success]).to be true
        expect(results[1][:success]).to be false
      end

      it 'logs partial success' do
        expect { uploader.upload_batch(urls, images) }
          .to output(%r{Batch upload completed: 1/2 successful}).to_stdout
      end
    end

    context 'with all failed uploads' do
      before do
        stub_request(:put, urls[0]).to_return(status: 403)
        stub_request(:put, urls[1]).to_return(status: 500)
      end

      it 'returns all failures' do
        results = uploader.upload_batch(urls, images)
        expect(results.all? { |r| !r[:success] }).to be true
      end

      it 'logs zero successful uploads' do
        expect { uploader.upload_batch(urls, images) }
          .to output(%r{Batch upload completed: 0/2 successful}).to_stdout
      end
    end
  end

  describe '#upload_images_from_files' do
    let(:destination_url) { 'https://s3.amazonaws.com/bucket/output/?signed=true' }
    let(:temp_files) do
      [
        Tempfile.new(['page-1', '.png']),
        Tempfile.new(['page-2', '.png'])
      ]
    end
    let(:image_paths) { temp_files.map(&:path) }

    before do
      temp_files.each_with_index do |file, index|
        file.write("fake-image-content-#{index + 1}")
        file.rewind
      end

      stub_request(:put, %r{https://s3.amazonaws.com/bucket/output/page-\d+.png})
        .to_return(status: 200, headers: { 'ETag' => '"test-etag"' })
    end

    after do
      temp_files.each(&:close!)
    end

    context 'with successful upload' do
      it 'returns success with uploaded URLs' do
        result = uploader.upload_images_from_files(destination_url, image_paths)
        expect(result[:success]).to be true
        expect(result[:uploaded_urls]).to be_an(Array)
        expect(result[:uploaded_urls].size).to eq(2)
      end

      it 'returns ETags for uploaded images' do
        result = uploader.upload_images_from_files(destination_url, image_paths)
        expect(result[:etags]).to be_an(Array)
        expect(result[:etags].size).to eq(2)
      end

      it 'strips query parameters from URLs' do
        result = uploader.upload_images_from_files(destination_url, image_paths)
        result[:uploaded_urls].each do |url|
          expect(url).not_to include('signed=')
        end
      end

      it 'generates sequential page names' do
        result = uploader.upload_images_from_files(destination_url, image_paths)
        expect(result[:uploaded_urls][0]).to include('page-1.png')
        expect(result[:uploaded_urls][1]).to include('page-2.png')
      end
    end

    context 'with destination URL ending in slash' do
      let(:destination_url) { 'https://s3.amazonaws.com/bucket/output/?signed=true' }

      it 'handles URL with trailing slash' do
        result = uploader.upload_images_from_files(destination_url, image_paths)
        expect(result[:success]).to be true
      end
    end

    context 'with destination URL not ending in slash' do
      let(:destination_url) { 'https://s3.amazonaws.com/bucket/output?signed=true' }

      it 'adds trailing slash to path' do
        result = uploader.upload_images_from_files(destination_url, image_paths)
        expect(result[:success]).to be true
        result[:uploaded_urls].each do |url|
          expect(url).to match(%r{/output/page-\d+\.png})
        end
      end
    end

    context 'with some failed uploads' do
      before do
        stub_request(:put, %r{https://s3.amazonaws.com/bucket/output/page-1.png})
          .to_return(status: 200, headers: { 'ETag' => '"etag-1"' })
        stub_request(:put, %r{https://s3.amazonaws.com/bucket/output/page-2.png})
          .to_return(status: 403, body: 'Forbidden')
      end

      it 'returns error with count' do
        result = uploader.upload_images_from_files(destination_url, image_paths)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Failed to upload 1 images')
      end

      it 'includes error messages' do
        result = uploader.upload_images_from_files(destination_url, image_paths)
        expect(result[:error]).to include('Access denied')
      end
    end

    context 'with file read error' do
      let(:invalid_paths) { ['/nonexistent/file1.png', '/nonexistent/file2.png'] }

      it 'returns error for missing files' do
        result = uploader.upload_images_from_files(destination_url, invalid_paths)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Upload error')
      end
    end

    context 'with URI parse error' do
      let(:invalid_url) { 'not a valid url' }

      it 'returns error for invalid destination URL' do
        result = uploader.upload_images_from_files(invalid_url, image_paths)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Upload error')
      end
    end
  end

  describe '#validate_inputs (private)' do
    context 'with valid inputs' do
      it 'does not raise error' do
        expect { uploader.send(:validate_inputs, url, content) }.not_to raise_error
      end
    end

    context 'with nil URL' do
      it 'raises ArgumentError' do
        expect { uploader.send(:validate_inputs, nil, content) }
          .to raise_error(ArgumentError, /URL cannot be nil or empty/)
      end
    end

    context 'with empty URL' do
      it 'raises ArgumentError' do
        expect { uploader.send(:validate_inputs, '', content) }
          .to raise_error(ArgumentError, /URL cannot be nil or empty/)
      end
    end

    context 'with nil content' do
      it 'raises ArgumentError' do
        expect { uploader.send(:validate_inputs, url, nil) }
          .to raise_error(ArgumentError, /Content cannot be nil or empty/)
      end
    end

    context 'with empty content' do
      it 'raises ArgumentError' do
        expect { uploader.send(:validate_inputs, url, '') }
          .to raise_error(ArgumentError, /Content cannot be nil or empty/)
      end
    end
  end

  describe '#upload_with_retry (private)' do
    let(:uri) { URI.parse(url) }

    context 'when upload succeeds on first try' do
      before do
        stub_request(:put, url)
          .to_return(status: 200, headers: { 'ETag' => '"test-etag"' })
      end

      it 'returns etag' do
        etag = uploader.send(:upload_with_retry, uri, content, 'image/png')
        expect(etag).to eq('"test-etag"')
      end
    end

    context 'when RetryHandler raises RetryError' do
      before do
        stub_request(:put, url).to_timeout.times(3)
      end

      it 'raises StandardError' do
        expect { uploader.send(:upload_with_retry, uri, content, 'image/png') }
          .to raise_error(StandardError, /execution expired/)
      end
    end
  end

  describe '#perform_upload (private)' do
    let(:uri) { URI.parse(url) }

    context 'with successful upload' do
      before do
        stub_request(:put, url)
          .to_return(status: 200, headers: { 'ETag' => '"upload-etag"' })
      end

      it 'returns ETag' do
        etag = uploader.send(:perform_upload, uri, content, 'image/png')
        expect(etag).to eq('"upload-etag"')
      end
    end

    context 'with lowercase etag header' do
      before do
        stub_request(:put, url)
          .to_return(status: 200, headers: { 'etag' => '"lowercase-etag"' })
      end

      it 'returns lowercase etag' do
        etag = uploader.send(:perform_upload, uri, content, 'image/png')
        expect(etag).to eq('"lowercase-etag"')
      end
    end

    context 'with no etag header' do
      before do
        stub_request(:put, url)
          .to_return(status: 200, headers: {})
      end

      it 'returns no-etag placeholder' do
        etag = uploader.send(:perform_upload, uri, content, 'image/png')
        expect(etag).to eq('no-etag')
      end
    end

    context 'with redirect response' do
      before do
        stub_request(:put, url)
          .to_return(status: 301, headers: { 'Location' => 'https://new-url.com' })
      end

      it 'raises error for redirect' do
        expect { uploader.send(:perform_upload, uri, content, 'image/png') }
          .to raise_error(StandardError, /Unexpected redirect/)
      end
    end

    context 'with error response' do
      before do
        stub_request(:put, url)
          .to_return(status: 400, body: 'Bad Request')
      end

      it 'raises error for 400' do
        expect { uploader.send(:perform_upload, uri, content, 'image/png') }
          .to raise_error(StandardError, /HTTP 400/)
      end
    end

    context 'with HTTPS URL' do
      let(:https_uri) { URI.parse('https://secure.example.com/image.png') }

      before do
        stub_request(:put, 'https://secure.example.com/image.png')
          .to_return(status: 200, headers: { 'ETag' => '"test"' })
      end

      it 'uses SSL for HTTPS' do
        uploader.send(:perform_upload, https_uri, content, 'image/png')
        expect(WebMock).to have_requested(:put, 'https://secure.example.com/image.png')
      end
    end

    context 'with HTTP URL' do
      let(:http_uri) { URI.parse('http://localhost:4566/image.png') }

      before do
        stub_request(:put, 'http://localhost:4566/image.png')
          .to_return(status: 200, headers: { 'ETag' => '"test"' })
      end

      it 'does not use SSL for HTTP' do
        uploader.send(:perform_upload, http_uri, content, 'image/png')
        expect(WebMock).to have_requested(:put, 'http://localhost:4566/image.png')
      end
    end
  end

  describe '#parse_destination_url (private)' do
    context 'with URL ending in slash' do
      let(:url_with_slash) { 'https://s3.amazonaws.com/bucket/output/' }

      it 'keeps trailing slash' do
        uri = uploader.send(:parse_destination_url, url_with_slash)
        expect(uri.path).to end_with('/')
      end
    end

    context 'with URL not ending in slash' do
      let(:url_without_slash) { 'https://s3.amazonaws.com/bucket/output' }

      it 'adds trailing slash' do
        uri = uploader.send(:parse_destination_url, url_without_slash)
        expect(uri.path).to end_with('/')
      end
    end
  end

  describe '#prepare_images_for_upload (private)' do
    let(:base_uri) { URI.parse('https://s3.amazonaws.com/bucket/output/') }
    let(:temp_files) do
      [
        Tempfile.new(['test-1', '.png']),
        Tempfile.new(['test-2', '.png'])
      ]
    end
    let(:image_paths) { temp_files.map(&:path) }

    before do
      temp_files.each_with_index do |file, index|
        file.write("content-#{index + 1}")
        file.rewind
      end
    end

    after do
      temp_files.each(&:close!)
    end

    it 'returns arrays of URLs and contents' do
      urls, contents = uploader.send(:prepare_images_for_upload, image_paths, base_uri)
      expect(urls).to be_an(Array)
      expect(contents).to be_an(Array)
      expect(urls.size).to eq(2)
      expect(contents.size).to eq(2)
    end

    it 'generates sequential page names' do
      urls, _contents = uploader.send(:prepare_images_for_upload, image_paths, base_uri)
      expect(urls[0]).to include('page-1.png')
      expect(urls[1]).to include('page-2.png')
    end

    it 'reads file contents' do
      _urls, contents = uploader.send(:prepare_images_for_upload, image_paths, base_uri)
      expect(contents[0]).to eq('content-1')
      expect(contents[1]).to eq('content-2')
    end
  end

  describe '#process_upload_results (private)' do
    let(:image_urls) { ['https://s3.amazonaws.com/bucket/page-1.png?signed=true', 'https://s3.amazonaws.com/bucket/page-2.png?signed=true'] }

    context 'with all successful uploads' do
      let(:upload_results) do
        [
          { success: true, etag: '"etag-1"', index: 0 },
          { success: true, etag: '"etag-2"', index: 1 }
        ]
      end

      it 'returns success result' do
        result = uploader.send(:process_upload_results, upload_results, image_urls)
        expect(result[:success]).to be true
      end

      it 'returns uploaded URLs without query params' do
        result = uploader.send(:process_upload_results, upload_results, image_urls)
        result[:uploaded_urls].each do |url|
          expect(url).not_to include('signed=')
        end
      end

      it 'returns all ETags' do
        result = uploader.send(:process_upload_results, upload_results, image_urls)
        expect(result[:etags]).to eq(['"etag-1"', '"etag-2"'])
      end
    end

    context 'with some failed uploads' do
      let(:upload_results) do
        [
          { success: true, etag: '"etag-1"', index: 0 },
          { success: false, error: 'Access denied - URL may be expired or invalid', index: 1 }
        ]
      end

      it 'returns failure result' do
        result = uploader.send(:process_upload_results, upload_results, image_urls)
        expect(result[:success]).to be false
      end

      it 'includes error count' do
        result = uploader.send(:process_upload_results, upload_results, image_urls)
        expect(result[:error]).to include('Failed to upload 1 images')
      end

      it 'includes error messages' do
        result = uploader.send(:process_upload_results, upload_results, image_urls)
        expect(result[:error]).to include('Access denied')
      end
    end

    context 'with multiple duplicate errors' do
      let(:upload_results) do
        [
          { success: false, error: 'HTTP 403: Forbidden', index: 0 },
          { success: false, error: 'HTTP 403: Forbidden', index: 1 }
        ]
      end

      it 'deduplicates error messages' do
        result = uploader.send(:process_upload_results, upload_results, image_urls)
        # Should only include the error message once
        expect(result[:error].scan('HTTP 403').count).to eq(1)
      end
    end
  end

  describe '#error_result (private)' do
    it 'returns hash with success false' do
      result = uploader.send(:error_result, 'Test error')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('Test error')
    end

    it 'logs error message' do
      expect { uploader.send(:error_result, 'Test error') }
        .to output(/Test error/).to_stdout
    end
  end

  describe '#log_info (private)' do
    it 'outputs info message' do
      expect { uploader.send(:log_info, 'Test info') }
        .to output(/Test info/).to_stdout
    end
  end

  describe '#log_error (private)' do
    it 'outputs error message' do
      expect { uploader.send(:log_error, 'Test error') }
        .to output(/Test error/).to_stdout
    end
  end
end

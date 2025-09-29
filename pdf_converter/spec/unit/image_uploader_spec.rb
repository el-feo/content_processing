# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'async'
require_relative '../../image_uploader'

RSpec.describe ImageUploader do
  let(:uploader) { described_class.new }
  let(:image_content) { File.read(File.expand_path('../fixtures/sample.png', __dir__), mode: 'rb') }

  describe '#upload' do
    let(:valid_url) { 'https://bucket.s3.amazonaws.com/output/page-1.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Expires=3600&X-Amz-Signature=abc123' }

    context 'with valid pre-signed URL' do
      it 'uploads image successfully' do
        stub_request(:put, /bucket\.s3\.amazonaws\.com/)
          .with(
            body: image_content,
            headers: { 'Content-Type' => 'image/png' }
          )
          .to_return(status: 200, body: '', headers: { 'ETag' => '"abc123"' })

        result = uploader.upload(valid_url, image_content, 'image/png')

        expect(result[:success]).to be true
        expect(result[:etag]).to eq('"abc123"')
      end

      it 'retries on transient failures' do
        stub_request(:put, /bucket\.s3\.amazonaws\.com/)
          .to_return(status: 503, body: 'Service Unavailable')
          .to_return(status: 503, body: 'Service Unavailable')
          .to_return(status: 200, body: '', headers: { 'ETag' => '"abc123"' })

        result = uploader.upload(valid_url, image_content, 'image/png')

        expect(result[:success]).to be true
        expect(a_request(:put, /bucket\.s3\.amazonaws\.com/)).to have_been_made.times(3)
      end

      it 'fails after max retries' do
        stub_request(:put, /bucket\.s3\.amazonaws\.com/)
          .to_return(status: 503, body: 'Service Unavailable').times(3)

        result = uploader.upload(valid_url, image_content, 'image/png')

        expect(result[:success]).to be false
        expect(result[:error]).to include('after 3 attempts')
      end
    end

    context 'with expired URL' do
      it 'returns appropriate error for 403 response' do
        stub_request(:put, /bucket\.s3\.amazonaws\.com/)
          .to_return(status: 403, body: 'Request has expired')

        result = uploader.upload(valid_url, image_content, 'image/png')

        expect(result[:success]).to be false
        expect(result[:error]).to include('Access denied')
      end
    end

    context 'with invalid URL' do
      it 'handles invalid URL format' do
        result = uploader.upload('not-a-url', image_content, 'image/png')

        expect(result[:success]).to be false
        expect(result[:error]).to include('Upload failed')
      end

      it 'handles nil URL' do
        result = uploader.upload(nil, image_content, 'image/png')

        expect(result[:success]).to be false
        expect(result[:error]).to include('cannot be nil')
      end
    end
  end

  describe '#upload_batch' do
    let(:urls) do
      [
        'https://bucket.s3.amazonaws.com/output/page-1.png?X-Amz-Algorithm=AWS4-HMAC-SHA256',
        'https://bucket.s3.amazonaws.com/output/page-2.png?X-Amz-Algorithm=AWS4-HMAC-SHA256'
      ]
    end
    let(:images) { [image_content, image_content] }

    it 'uploads multiple images concurrently' do
      stub_request(:put, /page-1\.png/)
        .to_return(status: 200, headers: { 'ETag' => '"etag1"' })
      stub_request(:put, /page-2\.png/)
        .to_return(status: 200, headers: { 'ETag' => '"etag2"' })

      results = uploader.upload_batch(urls, images, 'image/png')

      expect(results.size).to eq(2)
      expect(results.all? { |r| r[:success] }).to be true
      expect(results[0][:etag]).to eq('"etag1"')
      expect(results[1][:etag]).to eq('"etag2"')
    end

    it 'continues uploading even if one fails' do
      stub_request(:put, /page-1\.png/)
        .to_return(status: 403, body: 'Forbidden')
      stub_request(:put, /page-2\.png/)
        .to_return(status: 200, headers: { 'ETag' => '"etag2"' })

      results = uploader.upload_batch(urls, images, 'image/png')

      expect(results[0][:success]).to be false
      expect(results[1][:success]).to be true
    end
  end
end
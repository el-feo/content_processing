# frozen_string_literal: true

require 'spec_helper'
require_relative '../../app/response_builder'

RSpec.describe ResponseBuilder do
  let(:response_builder) { described_class.new }

  describe 'CORS_HEADERS' do
    it 'includes Content-Type header' do
      expect(ResponseBuilder::CORS_HEADERS['Content-Type']).to eq('application/json')
    end

    it 'includes CORS allow origin header' do
      expect(ResponseBuilder::CORS_HEADERS['Access-Control-Allow-Origin']).to eq('*')
    end

    it 'is frozen' do
      expect(ResponseBuilder::CORS_HEADERS).to be_frozen
    end
  end

  describe '#error_response' do
    context 'with 400 status code' do
      let(:response) { response_builder.error_response(400, 'Bad Request') }

      it 'returns correct status code' do
        expect(response[:statusCode]).to eq(400)
      end

      it 'includes CORS headers' do
        expect(response[:headers]).to eq(ResponseBuilder::CORS_HEADERS)
      end

      it 'includes error message in body' do
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('Bad Request')
      end

      it 'returns valid JSON body' do
        expect { JSON.parse(response[:body]) }.not_to raise_error
      end
    end

    context 'with 422 status code' do
      let(:response) { response_builder.error_response(422, 'Unprocessable Entity') }

      it 'returns correct status code' do
        expect(response[:statusCode]).to eq(422)
      end

      it 'includes error message in body' do
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('Unprocessable Entity')
      end
    end

    context 'with 500 status code' do
      let(:response) { response_builder.error_response(500, 'Internal Server Error') }

      it 'returns correct status code' do
        expect(response[:statusCode]).to eq(500)
      end

      it 'includes error message in body' do
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('Internal Server Error')
      end
    end

    context 'with special characters in message' do
      let(:response) { response_builder.error_response(400, "Invalid: \n\t\"quoted\"") }

      it 'properly escapes special characters in JSON' do
        body = JSON.parse(response[:body])
        expect(body['error']).to eq("Invalid: \n\t\"quoted\"")
      end
    end

    context 'with empty message' do
      let(:response) { response_builder.error_response(400, '') }

      it 'handles empty error message' do
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('')
      end
    end
  end

  describe '#authentication_error_response' do
    context 'when error is authentication failure' do
      let(:error_message) { 'Invalid token' }
      let(:response) { response_builder.authentication_error_response(error_message) }

      it 'returns 401 status code' do
        expect(response[:statusCode]).to eq(401)
      end

      it 'includes CORS headers' do
        expect(response[:headers]).to eq(ResponseBuilder::CORS_HEADERS)
      end

      it 'includes error message in body' do
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('Invalid token')
      end

      it 'returns valid JSON body' do
        expect { JSON.parse(response[:body]) }.not_to raise_error
      end
    end

    context 'when error contains "service" keyword' do
      let(:error_message) { 'Authentication service unavailable' }
      let(:response) { response_builder.authentication_error_response(error_message) }

      it 'returns 500 status code for service errors' do
        expect(response[:statusCode]).to eq(500)
      end

      it 'includes error message in body' do
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('Authentication service unavailable')
      end
    end

    context 'when error contains "service" in different case' do
      let(:error_message) { 'Service is down' }
      let(:response) { response_builder.authentication_error_response(error_message) }

      it 'returns 500 status code for service errors with different case' do
        expect(response[:statusCode]).to eq(500)
      end
    end

    context 'when error message is about token expiry' do
      let(:error_message) { 'Token has expired' }
      let(:response) { response_builder.authentication_error_response(error_message) }

      it 'returns 401 status code for expired token' do
        expect(response[:statusCode]).to eq(401)
      end
    end

    context 'when error message is about missing header' do
      let(:error_message) { 'Missing Authorization header' }
      let(:response) { response_builder.authentication_error_response(error_message) }

      it 'returns 401 status code for missing header' do
        expect(response[:statusCode]).to eq(401)
      end
    end

    context 'when error message is about invalid signature' do
      let(:error_message) { 'Invalid signature' }
      let(:response) { response_builder.authentication_error_response(error_message) }

      it 'returns 401 status code for invalid signature' do
        expect(response[:statusCode]).to eq(401)
      end
    end
  end

  describe '#success_response' do
    let(:params) do
      {
        unique_id: 'test-123',
        uploaded_urls: ['https://s3.amazonaws.com/bucket/page-1.png'],
        page_count: 1,
        metadata: { dpi: 300, compression: 6 }
      }
    end
    let(:response) { response_builder.success_response(**params) }

    it 'returns 200 status code' do
      expect(response[:statusCode]).to eq(200)
    end

    it 'includes CORS headers' do
      expect(response[:headers]).to eq(ResponseBuilder::CORS_HEADERS)
    end

    it 'includes success message in body' do
      body = JSON.parse(response[:body])
      expect(body['message']).to eq('PDF conversion and upload completed')
    end

    it 'includes unique_id in body' do
      body = JSON.parse(response[:body])
      expect(body['unique_id']).to eq('test-123')
    end

    it 'includes status in body' do
      body = JSON.parse(response[:body])
      expect(body['status']).to eq('completed')
    end

    it 'includes images array in body' do
      body = JSON.parse(response[:body])
      expect(body['images']).to eq(['https://s3.amazonaws.com/bucket/page-1.png'])
    end

    it 'includes page count in body' do
      body = JSON.parse(response[:body])
      expect(body['pages_converted']).to eq(1)
    end

    it 'includes metadata in body' do
      body = JSON.parse(response[:body])
      expect(body['metadata']).to eq({ 'dpi' => 300, 'compression' => 6 })
    end

    it 'returns valid JSON body' do
      expect { JSON.parse(response[:body]) }.not_to raise_error
    end

    context 'with multiple images' do
      let(:params) do
        {
          unique_id: 'multi-page-456',
          uploaded_urls: [
            'https://s3.amazonaws.com/bucket/page-1.png',
            'https://s3.amazonaws.com/bucket/page-2.png',
            'https://s3.amazonaws.com/bucket/page-3.png'
          ],
          page_count: 3,
          metadata: { dpi: 150, compression: 9 }
        }
      end

      it 'includes all uploaded URLs' do
        body = JSON.parse(response[:body])
        expect(body['images'].size).to eq(3)
        expect(body['pages_converted']).to eq(3)
      end
    end

    context 'with empty metadata' do
      let(:params) do
        {
          unique_id: 'test-789',
          uploaded_urls: ['https://s3.amazonaws.com/bucket/page-1.png'],
          page_count: 1,
          metadata: {}
        }
      end

      it 'handles empty metadata' do
        body = JSON.parse(response[:body])
        expect(body['metadata']).to eq({})
      end
    end

    context 'with complex metadata' do
      let(:params) do
        {
          unique_id: 'complex-metadata',
          uploaded_urls: ['https://s3.amazonaws.com/bucket/page-1.png'],
          page_count: 1,
          metadata: {
            dpi: 300,
            compression: 6,
            format: 'png',
            color_space: 'srgb',
            dimensions: { width: 2480, height: 3508 }
          }
        }
      end

      it 'preserves complex metadata structure' do
        body = JSON.parse(response[:body])
        expect(body['metadata']['dimensions']).to eq({ 'width' => 2480, 'height' => 3508 })
      end
    end
  end

  describe 'response structure consistency' do
    it 'all responses include required keys' do
      error_resp = response_builder.error_response(400, 'Error')
      auth_error_resp = response_builder.authentication_error_response('Auth Error')
      success_resp = response_builder.success_response(
        unique_id: 'test',
        uploaded_urls: [],
        page_count: 0,
        metadata: {}
      )

      [error_resp, auth_error_resp, success_resp].each do |resp|
        expect(resp).to have_key(:statusCode)
        expect(resp).to have_key(:headers)
        expect(resp).to have_key(:body)
        expect(resp[:headers]).to include('Content-Type', 'Access-Control-Allow-Origin')
      end
    end

    it 'all response bodies are valid JSON' do
      error_resp = response_builder.error_response(400, 'Error')
      auth_error_resp = response_builder.authentication_error_response('Auth Error')
      success_resp = response_builder.success_response(
        unique_id: 'test',
        uploaded_urls: [],
        page_count: 0,
        metadata: {}
      )

      [error_resp, auth_error_resp, success_resp].each do |resp|
        expect { JSON.parse(resp[:body]) }.not_to raise_error
      end
    end
  end
end

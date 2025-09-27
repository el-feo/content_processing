require 'spec_helper'
require_relative '../pdf_converter/app'

RSpec.describe 'PdfConverterHandler' do
  describe '#lambda_handler' do
    let(:context) { {} }

    context 'with valid request' do
      let(:valid_event) do
        {
          'body' => {
            'source' => 'https://example.com/source.pdf',
            'destination' => 'https://example.com/destination/',
            'webhook' => 'https://example.com/webhook',
            'unique_id' => 'test-123'
          }.to_json
        }
      end

      it 'returns success response' do
        response = lambda_handler(event: valid_event, context: context)

        expect(response[:statusCode]).to eq(200)

        body = JSON.parse(response[:body])
        expect(body['status']).to eq('accepted')
        expect(body['unique_id']).to eq('test-123')
        expect(body['message']).to eq('PDF conversion request received')
      end
    end

    context 'with missing required fields' do
      let(:invalid_event) do
        {
          'body' => {
            'source' => 'https://example.com/source.pdf'
          }.to_json
        }
      end

      it 'returns error for missing fields' do
        response = lambda_handler(event: invalid_event, context: context)

        expect(response[:statusCode]).to eq(400)

        body = JSON.parse(response[:body])
        expect(body['error']).to eq('Missing required fields')
      end
    end

    context 'with invalid URL format' do
      let(:invalid_url_event) do
        {
          'body' => {
            'source' => 'not-a-url',
            'destination' => 'https://example.com/destination/',
            'webhook' => 'https://example.com/webhook',
            'unique_id' => 'test-123'
          }.to_json
        }
      end

      it 'returns error for invalid URL' do
        response = lambda_handler(event: invalid_url_event, context: context)

        expect(response[:statusCode]).to eq(400)

        body = JSON.parse(response[:body])
        expect(body['error']).to eq('Invalid URL format')
      end
    end

    context 'with invalid JSON' do
      let(:invalid_json_event) do
        {
          'body' => 'not valid json'
        }
      end

      it 'returns error for invalid JSON' do
        response = lambda_handler(event: invalid_json_event, context: context)

        expect(response[:statusCode]).to eq(400)

        body = JSON.parse(response[:body])
        expect(body['error']).to eq('Invalid JSON format')
      end
    end
  end
end
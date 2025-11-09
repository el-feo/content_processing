# frozen_string_literal: true

require 'spec_helper'
require_relative '../../app/request_validator'
require_relative '../../app/response_builder'

RSpec.describe RequestValidator do
  let(:validator) { described_class.new }
  let(:response_builder) { ResponseBuilder.new }
  let(:url_validator) { instance_double(UrlValidator) }

  before do
    allow(UrlValidator).to receive(:new).and_return(url_validator)
  end

  describe 'REQUIRED_FIELDS' do
    it 'includes source field' do
      expect(RequestValidator::REQUIRED_FIELDS).to include('source')
    end

    it 'includes destination field' do
      expect(RequestValidator::REQUIRED_FIELDS).to include('destination')
    end

    it 'includes webhook field' do
      expect(RequestValidator::REQUIRED_FIELDS).to include('webhook')
    end

    it 'includes unique_id field' do
      expect(RequestValidator::REQUIRED_FIELDS).to include('unique_id')
    end

    it 'is frozen' do
      expect(RequestValidator::REQUIRED_FIELDS).to be_frozen
    end
  end

  describe 'UNIQUE_ID_PATTERN' do
    it 'matches valid alphanumeric strings' do
      expect('test123').to match(RequestValidator::UNIQUE_ID_PATTERN)
    end

    it 'matches strings with hyphens' do
      expect('test-123').to match(RequestValidator::UNIQUE_ID_PATTERN)
    end

    it 'matches strings with underscores' do
      expect('test_123').to match(RequestValidator::UNIQUE_ID_PATTERN)
    end

    it 'does not match strings with slashes' do
      expect('test/123').not_to match(RequestValidator::UNIQUE_ID_PATTERN)
    end

    it 'does not match strings with dots' do
      expect('../test').not_to match(RequestValidator::UNIQUE_ID_PATTERN)
    end

    it 'does not match strings with special characters' do
      expect('test@123').not_to match(RequestValidator::UNIQUE_ID_PATTERN)
    end
  end

  describe '#parse_request' do
    context 'when body is a JSON string' do
      let(:event) do
        {
          'body' => '{"source":"s3://bucket/file.pdf","destination":"s3://bucket/output/"}'
        }
      end

      it 'parses JSON string to hash' do
        result = validator.parse_request(event)
        expect(result).to be_a(Hash)
        expect(result['source']).to eq('s3://bucket/file.pdf')
      end
    end

    context 'when body is already a hash' do
      let(:event) do
        {
          'body' => {
            'source' => 's3://bucket/file.pdf',
            'destination' => 's3://bucket/output/'
          }
        }
      end

      it 'returns the hash directly' do
        result = validator.parse_request(event)
        expect(result).to be_a(Hash)
        expect(result['source']).to eq('s3://bucket/file.pdf')
      end
    end

    context 'when body is not present' do
      let(:event) do
        {
          'source' => 's3://bucket/file.pdf',
          'destination' => 's3://bucket/output/'
        }
      end

      it 'returns the event itself' do
        result = validator.parse_request(event)
        expect(result).to eq(event)
      end
    end

    context 'when body is nil' do
      let(:event) { { 'body' => nil } }

      it 'returns the event' do
        result = validator.parse_request(event)
        expect(result).to eq(event)
      end
    end
  end

  describe '#parse_request_body' do
    context 'with valid JSON string' do
      let(:event) do
        {
          'body' => '{"source":"https://s3.amazonaws.com/bucket/file.pdf","unique_id":"test-123"}'
        }
      end

      it 'returns parsed hash' do
        result = validator.parse_request_body(event, response_builder)
        expect(result).to be_a(Hash)
        expect(result['source']).to eq('https://s3.amazonaws.com/bucket/file.pdf')
      end
    end

    context 'with invalid JSON string' do
      let(:event) { { 'body' => 'not valid json {' } }

      it 'returns error response for invalid JSON' do
        result = validator.parse_request_body(event, response_builder)
        expect(result[:statusCode]).to eq(400)
        body = JSON.parse(result[:body])
        expect(body['error']).to eq('Invalid JSON format')
      end
    end

    context 'with malformed JSON' do
      let(:event) { { 'body' => '{"key": invalid}' } }

      it 'returns error response for malformed JSON' do
        result = validator.parse_request_body(event, response_builder)
        expect(result[:statusCode]).to eq(400)
        body = JSON.parse(result[:body])
        expect(body['error']).to eq('Invalid JSON format')
      end
    end

    context 'when unexpected error occurs' do
      let(:event) { { 'body' => 'valid json' } }

      before do
        allow(validator).to receive(:parse_request).and_raise(StandardError.new('Unexpected error'))
      end

      it 'returns generic error response' do
        result = validator.parse_request_body(event, response_builder)
        expect(result[:statusCode]).to eq(400)
        body = JSON.parse(result[:body])
        expect(body['error']).to eq('Invalid request')
      end
    end
  end

  describe '#validate' do
    let(:valid_body) do
      {
        'source' => 'https://s3.amazonaws.com/bucket/input.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256',
        'destination' => 'https://s3.amazonaws.com/bucket/output/?X-Amz-Algorithm=AWS4-HMAC-SHA256',
        'webhook' => 'https://example.com/webhook',
        'unique_id' => 'test-123'
      }
    end

    before do
      allow(url_validator).to receive(:valid_s3_signed_url?).and_return(true)
      allow(url_validator).to receive(:valid_s3_destination_url?).and_return(true)
      allow(url_validator).to receive(:valid_url?).and_return(true)
    end

    context 'with all valid fields' do
      it 'returns nil indicating validation passed' do
        result = validator.validate(valid_body, response_builder)
        expect(result).to be_nil
      end

      it 'calls URL validator for source' do
        validator.validate(valid_body, response_builder)
        expect(url_validator).to have_received(:valid_s3_signed_url?)
          .with('https://s3.amazonaws.com/bucket/input.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256')
      end

      it 'calls URL validator for destination' do
        validator.validate(valid_body, response_builder)
        expect(url_validator).to have_received(:valid_s3_destination_url?)
          .with('https://s3.amazonaws.com/bucket/output/?X-Amz-Algorithm=AWS4-HMAC-SHA256')
      end

      it 'calls URL validator for webhook' do
        validator.validate(valid_body, response_builder)
        expect(url_validator).to have_received(:valid_url?).with('https://example.com/webhook')
      end
    end

    context 'with missing source field' do
      let(:body) { valid_body.except('source') }

      it 'returns error response' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
        body_json = JSON.parse(result[:body])
        expect(body_json['error']).to eq('Missing required fields')
      end
    end

    context 'with missing destination field' do
      let(:body) { valid_body.except('destination') }

      it 'returns error response' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
      end
    end

    context 'with missing webhook field' do
      let(:body) { valid_body.except('webhook') }

      it 'returns error response' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
      end
    end

    context 'with missing unique_id field' do
      let(:body) { valid_body.except('unique_id') }

      it 'returns error response' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
      end
    end

    context 'with invalid unique_id format' do
      let(:body) { valid_body.merge('unique_id' => '../../../etc/passwd') }

      it 'returns error response for path traversal attempt' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
        body_json = JSON.parse(result[:body])
        expect(body_json['error']).to include('Invalid unique_id format')
      end
    end

    context 'with unique_id containing slashes' do
      let(:body) { valid_body.merge('unique_id' => 'test/123') }

      it 'returns error response' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
        body_json = JSON.parse(result[:body])
        expect(body_json['error']).to include('Invalid unique_id format')
      end
    end

    context 'with unique_id containing special characters' do
      let(:body) { valid_body.merge('unique_id' => 'test@#$%') }

      it 'returns error response' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
      end
    end

    context 'with valid unique_id using hyphens' do
      let(:body) { valid_body.merge('unique_id' => 'test-id-123') }

      it 'accepts unique_id with hyphens' do
        result = validator.validate(body, response_builder)
        expect(result).to be_nil
      end
    end

    context 'with valid unique_id using underscores' do
      let(:body) { valid_body.merge('unique_id' => 'test_id_123') }

      it 'accepts unique_id with underscores' do
        result = validator.validate(body, response_builder)
        expect(result).to be_nil
      end
    end

    context 'with invalid source URL' do
      let(:body) { valid_body }

      before do
        allow(url_validator).to receive(:valid_s3_signed_url?).and_return(false)
      end

      it 'returns error response for invalid source' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
        body_json = JSON.parse(result[:body])
        expect(body_json['error']).to include('Invalid source URL')
      end
    end

    context 'with invalid destination URL' do
      let(:body) { valid_body }

      before do
        allow(url_validator).to receive(:valid_s3_destination_url?).and_return(false)
      end

      it 'returns error response for invalid destination' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
        body_json = JSON.parse(result[:body])
        expect(body_json['error']).to include('Invalid destination URL')
      end
    end

    context 'with invalid webhook URL' do
      let(:body) { valid_body }

      before do
        allow(url_validator).to receive(:valid_url?).and_return(false)
      end

      it 'returns error response for invalid webhook' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
        body_json = JSON.parse(result[:body])
        expect(body_json['error']).to include('Invalid webhook URL')
      end
    end

    context 'with nil webhook (allowed)' do
      let(:body) { valid_body.merge('webhook' => nil) }

      it 'does not validate webhook when nil' do
        result = validator.validate(body, response_builder)
        # Should fail on missing required field instead
        expect(result[:statusCode]).to eq(400)
      end
    end

    context 'with empty string webhook' do
      let(:body) { valid_body.merge('webhook' => '') }

      before do
        allow(url_validator).to receive(:valid_url?).with('').and_return(false)
      end

      it 'validates empty webhook string' do
        result = validator.validate(body, response_builder)
        expect(result[:statusCode]).to eq(400)
      end
    end

    context 'validation order' do
      it 'checks required fields before format validation' do
        body = valid_body.except('source')
        result = validator.validate(body, response_builder)
        body_json = JSON.parse(result[:body])
        expect(body_json['error']).to eq('Missing required fields')
      end

      it 'checks unique_id format before URL validation' do
        body = valid_body.merge('unique_id' => '../invalid')
        allow(url_validator).to receive(:valid_s3_signed_url?).and_return(false)

        result = validator.validate(body, response_builder)
        body_json = JSON.parse(result[:body])
        expect(body_json['error']).to include('Invalid unique_id format')
      end
    end
  end

  describe 'initialization' do
    it 'creates a UrlValidator instance' do
      expect(UrlValidator).to receive(:new)
      described_class.new
    end
  end
end

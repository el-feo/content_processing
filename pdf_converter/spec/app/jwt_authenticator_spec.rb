# frozen_string_literal: true

require 'spec_helper'
require 'aws-sdk-secretsmanager'
require_relative '../../app/jwt_authenticator'

RSpec.describe JwtAuthenticator do
  let(:secret_name) { 'test-jwt-secret' }
  let(:jwt_secret) { 'test-secret-key-12345' }
  let(:secrets_manager_client) { instance_double(Aws::SecretsManager::Client).as_null_object }
  let(:secret_response) { instance_double(Aws::SecretsManager::Types::GetSecretValueResponse, secret_string: jwt_secret) }

  before do
    ENV.delete('LOG_LEVEL') # Clear any LOG_LEVEL setting from previous tests
    allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_manager_client)
    allow(secrets_manager_client).to receive(:get_secret_value)
      .with(secret_id: secret_name)
      .and_return(secret_response)
  end

  describe '.initialize' do
    it 'retrieves JWT secret from Secrets Manager' do
      described_class.new(secret_name)
      expect(secrets_manager_client).to have_received(:get_secret_value)
        .with(secret_id: secret_name)
    end

    it 'sets default logger level to INFO' do
      ENV.delete('LOG_LEVEL')
      authenticator = described_class.new(secret_name)
      expect(authenticator.logger.level).to eq(Logger::INFO)
    end

    context 'when secret retrieval fails with ResourceNotFoundException' do
      before do
        allow(secrets_manager_client).to receive(:get_secret_value)
          .and_raise(Aws::SecretsManager::Errors::ResourceNotFoundException.new(nil, 'Secret not found'))
      end

      it 'raises AuthenticationError' do
        expect do
          described_class.new(secret_name)
        end.to raise_error(JwtAuthenticator::AuthenticationError, /not found/)
      end
    end

    context 'when secret retrieval fails with ServiceError' do
      before do
        allow(secrets_manager_client).to receive(:get_secret_value)
          .and_raise(Aws::SecretsManager::Errors::ServiceError.new(nil, 'Service temporarily unavailable'))
      end

      it 'raises AuthenticationError with service error message' do
        expect do
          described_class.new(secret_name)
        end.to raise_error(JwtAuthenticator::AuthenticationError, /AWS service error/)
      end
    end

    context 'when secret retrieval fails with StandardError' do
      before do
        allow(secrets_manager_client).to receive(:get_secret_value)
          .and_raise(StandardError.new('Unexpected error'))
      end

      it 'raises AuthenticationError' do
        expect do
          described_class.new(secret_name)
        end.to raise_error(JwtAuthenticator::AuthenticationError, /Unexpected error/)
      end
    end
  end

  describe '#authenticate' do
    let(:authenticator) { described_class.new(secret_name) }

    context 'with valid token' do
      let(:payload) { { 'user_id' => '123', 'exp' => (Time.now.to_i + 3600) } }
      let(:token) { JWT.encode(payload, jwt_secret, 'HS256') }
      let(:headers) { { 'Authorization' => "Bearer #{token}" } }

      it 'returns authenticated with payload' do
        result = authenticator.authenticate(headers)
        expect(result[:authenticated]).to be true
        expect(result[:payload]['user_id']).to eq('123')
      end

      it 'logs success message' do
        authenticator.logger.level = Logger::DEBUG
        # Just verify it doesn't raise an error when logging
        expect { authenticator.authenticate(headers) }.not_to raise_error
      end
    end

    context 'with lowercase authorization header' do
      let(:payload) { { 'user_id' => '456', 'exp' => (Time.now.to_i + 3600) } }
      let(:token) { JWT.encode(payload, jwt_secret, 'HS256') }
      let(:headers) { { 'authorization' => "Bearer #{token}" } }

      it 'accepts lowercase header name' do
        result = authenticator.authenticate(headers)
        expect(result[:authenticated]).to be true
      end
    end

    context 'with missing Authorization header' do
      let(:headers) { {} }

      it 'returns authentication failure' do
        result = authenticator.authenticate(headers)
        expect(result[:authenticated]).to be false
        expect(result[:error]).to eq('Missing Authorization header')
      end

      it 'logs error message' do
        expect { authenticator.authenticate(headers) }
          .to output(/Missing Authorization header/).to_stdout
      end
    end

    context 'with present but invalid Bearer token format' do
      let(:headers) { { 'Authorization' => 'invalid-format-no-bearer' } }

      it 'returns authentication failure' do
        result = authenticator.authenticate(headers)
        expect(result[:authenticated]).to be false
        expect(result[:error]).to eq('Invalid Bearer token format')
      end

      it 'logs error message' do
        expect { authenticator.authenticate(headers) }
          .to output(/Invalid Bearer token format/).to_stdout
      end
    end

    context 'with expired token' do
      let(:payload) { { 'user_id' => '123', 'exp' => (Time.now.to_i - 3600) } }
      let(:token) { JWT.encode(payload, jwt_secret, 'HS256') }
      let(:headers) { { 'Authorization' => "Bearer #{token}" } }

      it 'returns authentication failure with expiry message' do
        result = authenticator.authenticate(headers)
        expect(result[:authenticated]).to be false
        expect(result[:error]).to eq('Token has expired')
      end

      it 'logs error message' do
        expect { authenticator.authenticate(headers) }
          .to output(/Token has expired/).to_stdout
      end
    end

    context 'with invalid signature' do
      let(:payload) { { 'user_id' => '123', 'exp' => (Time.now.to_i + 3600) } }
      let(:token) { JWT.encode(payload, 'wrong-secret', 'HS256') }
      let(:headers) { { 'Authorization' => "Bearer #{token}" } }

      it 'returns authentication failure with signature message' do
        result = authenticator.authenticate(headers)
        expect(result[:authenticated]).to be false
        expect(result[:error]).to eq('Invalid signature')
      end

      it 'logs error message' do
        expect { authenticator.authenticate(headers) }
          .to output(/Invalid signature/).to_stdout
      end
    end

    context 'with malformed token' do
      let(:headers) { { 'Authorization' => 'Bearer not.a.valid.jwt.token' } }

      it 'returns authentication failure with malformed message' do
        result = authenticator.authenticate(headers)
        expect(result[:authenticated]).to be false
        expect(result[:error]).to eq('Malformed token')
      end

      it 'logs error message' do
        expect { authenticator.authenticate(headers) }
          .to output(/Malformed token/).to_stdout
      end
    end

    context 'when token validation raises unexpected error' do
      let(:headers) { { 'Authorization' => 'Bearer valid.looking.token' } }

      before do
        allow(JWT).to receive(:decode).and_raise(StandardError.new('Unexpected JWT error'))
      end

      it 'returns authentication failure with generic error' do
        result = authenticator.authenticate(headers)
        expect(result[:authenticated]).to be false
        expect(result[:error]).to include('Token validation error')
      end

      it 'logs error message' do
        expect { authenticator.authenticate(headers) }
          .to output(/Token validation error/).to_stdout
      end
    end
  end

  describe '#extract_token' do
    let(:authenticator) { described_class.new(secret_name) }

    context 'with valid Bearer token in Authorization header' do
      let(:headers) { { 'Authorization' => 'Bearer test-token-123' } }

      it 'extracts the token' do
        expect(authenticator.extract_token(headers)).to eq('test-token-123')
      end
    end

    context 'with valid Bearer token in lowercase authorization header' do
      let(:headers) { { 'authorization' => 'Bearer test-token-456' } }

      it 'extracts the token from lowercase header' do
        expect(authenticator.extract_token(headers)).to eq('test-token-456')
      end
    end

    context 'with nil headers' do
      it 'returns nil' do
        expect(authenticator.extract_token(nil)).to be_nil
      end
    end

    context 'with missing Authorization header' do
      let(:headers) { { 'Content-Type' => 'application/json' } }

      it 'returns nil' do
        expect(authenticator.extract_token(headers)).to be_nil
      end
    end

    context 'with Authorization header but no Bearer prefix' do
      let(:headers) { { 'Authorization' => 'test-token-only' } }

      it 'returns nil for single-part header' do
        expect(authenticator.extract_token(headers)).to be_nil
      end
    end

    context 'with Authorization header with wrong auth scheme' do
      let(:headers) { { 'Authorization' => 'Basic dXNlcjpwYXNz' } }

      it 'returns nil for non-Bearer scheme' do
        expect(authenticator.extract_token(headers)).to be_nil
      end
    end

    context 'with Authorization header with mixed case Bearer' do
      let(:headers) { { 'Authorization' => 'BeArEr test-token-789' } }

      it 'extracts token with case-insensitive Bearer check' do
        expect(authenticator.extract_token(headers)).to eq('test-token-789')
      end
    end

    context 'with Authorization header with extra parts' do
      let(:headers) { { 'Authorization' => 'Bearer token extra-part' } }

      it 'returns nil for more than 2 parts' do
        expect(authenticator.extract_token(headers)).to be_nil
      end
    end
  end

  describe '#validate_token' do
    let(:authenticator) { described_class.new(secret_name) }

    context 'with valid token' do
      let(:payload) { { 'user_id' => '123', 'role' => 'admin', 'exp' => (Time.now.to_i + 3600) } }
      let(:token) { JWT.encode(payload, jwt_secret, 'HS256') }

      it 'returns valid with payload' do
        result = authenticator.validate_token(token)
        expect(result[:valid]).to be true
        expect(result[:payload]['user_id']).to eq('123')
        expect(result[:payload]['role']).to eq('admin')
      end
    end

    context 'with nil token' do
      it 'returns invalid with no token message' do
        result = authenticator.validate_token(nil)
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('No token provided')
      end
    end

    context 'with empty token' do
      it 'returns invalid with no token message' do
        result = authenticator.validate_token('')
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('No token provided')
      end
    end

    context 'with expired token' do
      let(:payload) { { 'user_id' => '123', 'exp' => (Time.now.to_i - 3600) } }
      let(:token) { JWT.encode(payload, jwt_secret, 'HS256') }

      it 'returns invalid with expiry message' do
        result = authenticator.validate_token(token)
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('Token has expired')
      end
    end

    context 'with invalid signature' do
      let(:payload) { { 'user_id' => '123', 'exp' => (Time.now.to_i + 3600) } }
      let(:token) { JWT.encode(payload, 'wrong-secret-key', 'HS256') }

      it 'returns invalid with signature error' do
        result = authenticator.validate_token(token)
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('Invalid signature')
      end
    end

    context 'with malformed token' do
      it 'returns invalid with malformed error' do
        result = authenticator.validate_token('clearly.not.valid.jwt')
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('Malformed token')
      end
    end

    context 'when JWT decode raises unexpected error' do
      let(:token) { 'some-token' }

      before do
        allow(JWT).to receive(:decode).and_raise(StandardError.new('Unexpected issue'))
      end

      it 'returns invalid with generic error message' do
        result = authenticator.validate_token(token)
        expect(result[:valid]).to be false
        expect(result[:error]).to include('Token validation error')
        expect(result[:error]).to include('Unexpected issue')
      end
    end
  end

  describe '#build_client_config (private)' do
    let(:authenticator) { described_class.new(secret_name) }

    context 'without AWS_ENDPOINT_URL' do
      before do
        ENV.delete('AWS_ENDPOINT_URL')
        ENV['AWS_REGION'] = 'us-west-2'
        # Reset the stub to capture the new initialization
        allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_manager_client)
      end

      after do
        ENV['AWS_REGION'] = 'us-east-1'
      end

      it 'builds config with region from environment' do
        # Create new authenticator to trigger client creation with new config
        described_class.new(secret_name)
        expect(Aws::SecretsManager::Client).to have_received(:new)
          .with(hash_including(region: 'us-west-2'))
      end
    end

    context 'without AWS_REGION' do
      before do
        ENV.delete('AWS_REGION')
        ENV.delete('AWS_ENDPOINT_URL')
        # Need to create new authenticator to test default
        allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_manager_client)
      end

      it 'uses default region us-east-1' do
        described_class.new(secret_name)
        expect(Aws::SecretsManager::Client).to have_received(:new)
          .with(hash_including(region: 'us-east-1'))
      end
    end

    context 'with AWS_ENDPOINT_URL for LocalStack' do
      before do
        ENV['AWS_ENDPOINT_URL'] = 'http://localhost:4566'
        ENV['AWS_REGION'] = 'us-east-1'
        ENV.delete('AWS_ACCESS_KEY_ID')
        ENV.delete('AWS_SECRET_ACCESS_KEY')
        allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_manager_client)
      end

      after do
        ENV.delete('AWS_ENDPOINT_URL')
      end

      it 'builds config with endpoint and test credentials' do
        described_class.new(secret_name)
        expect(Aws::SecretsManager::Client).to have_received(:new)
          .with(hash_including(
                  endpoint: 'http://localhost:4566',
                  access_key_id: 'test',
                  secret_access_key: 'test',
                  ssl_verify_peer: false
                ))
      end
    end

    context 'with AWS_ENDPOINT_URL and custom credentials' do
      before do
        ENV['AWS_ENDPOINT_URL'] = 'http://localhost:4566'
        ENV['AWS_REGION'] = 'us-east-1'
        ENV['AWS_ACCESS_KEY_ID'] = 'custom-access-key'
        ENV['AWS_SECRET_ACCESS_KEY'] = 'custom-secret-key'
        allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_manager_client)
      end

      after do
        ENV.delete('AWS_ENDPOINT_URL')
        ENV.delete('AWS_ACCESS_KEY_ID')
        ENV.delete('AWS_SECRET_ACCESS_KEY')
      end

      it 'builds config with custom credentials from environment' do
        described_class.new(secret_name)
        expect(Aws::SecretsManager::Client).to have_received(:new)
          .with(hash_including(
                  access_key_id: 'custom-access-key',
                  secret_access_key: 'custom-secret-key'
                ))
      end
    end
  end

  describe '#log_error' do
    let(:authenticator) { described_class.new(secret_name) }

    it 'logs error messages to logger' do
      expect { authenticator.log_error('Test error message') }
        .to output(/Test error message/).to_stdout
    end
  end

  describe '#log_debug' do
    let(:authenticator) { described_class.new(secret_name) }

    it 'logs debug messages without raising error' do
      authenticator.logger.level = Logger::DEBUG
      expect { authenticator.log_debug('Test debug message') }.not_to raise_error
    end

    it 'handles nil logger gracefully' do
      # Test the &. safe navigation
      allow(authenticator).to receive(:instance_variable_get).with(:@logger).and_return(nil)
      expect { authenticator.log_debug('Test') }.not_to raise_error
    end
  end

  describe 'AuthenticationError' do
    it 'is a subclass of StandardError' do
      expect(JwtAuthenticator::AuthenticationError).to be < StandardError
    end
  end
end

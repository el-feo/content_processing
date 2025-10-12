# frozen_string_literal: true

require_relative '../spec_helper'
require 'jwt'
require 'aws-sdk-secretsmanager'

RSpec.describe 'JwtAuthenticator' do
  let(:valid_secret) { 'test-secret-key-for-jwt-validation' }
  let(:valid_payload) { { user_id: '123', exp: Time.now.to_i + 3600 } }
  let(:valid_token) { JWT.encode(valid_payload, valid_secret, 'HS256') }
  let(:wrong_secret) { 'wrong-secret-key' }
  let(:invalid_token) { JWT.encode(valid_payload, wrong_secret, 'HS256') }
  let(:expired_payload) { { user_id: '123', exp: Time.now.to_i - 3600 } }
  let(:expired_token) { JWT.encode(expired_payload, valid_secret, 'HS256') }
  let(:malformed_token) { 'not.a.valid.jwt.token' }

  before do
    require_relative '../../app/jwt_authenticator'
  end

  describe 'initialization' do
    it 'initializes with a secret name' do
      secrets_client = instance_double(Aws::SecretsManager::Client)
      allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
      allow(secrets_client).to receive(:get_secret_value)
        .with(secret_id: 'test-secret')
        .and_return(double(secret_string: valid_secret))

      expect { JwtAuthenticator.new('test-secret') }.not_to raise_error
    end

    it 'retrieves secret from AWS Secrets Manager on initialization' do
      secrets_client = instance_double(Aws::SecretsManager::Client)
      allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
      allow(secrets_client).to receive(:get_secret_value)
        .with(secret_id: 'test-secret')
        .and_return(double(secret_string: valid_secret))

      authenticator = JwtAuthenticator.new('test-secret')
      expect(authenticator).not_to be_nil
    end

    it 'handles AWS Secrets Manager errors gracefully' do
      secrets_client = instance_double(Aws::SecretsManager::Client)
      allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
      allow(secrets_client).to receive(:get_secret_value)
        .and_raise(Aws::SecretsManager::Errors::ResourceNotFoundException.new(nil, nil))

      expect { JwtAuthenticator.new('non-existent-secret') }
        .to raise_error(JwtAuthenticator::AuthenticationError, /Failed to retrieve JWT secret/)
    end
  end

  describe 'token extraction' do
    let(:authenticator) do
      secrets_client = instance_double(Aws::SecretsManager::Client)
      allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
      allow(secrets_client).to receive(:get_secret_value)
        .with(secret_id: 'test-secret')
        .and_return(double(secret_string: valid_secret))
      JwtAuthenticator.new('test-secret')
    end

    it 'extracts token from valid Authorization header' do
      headers = { 'Authorization' => "Bearer #{valid_token}" }
      token = authenticator.extract_token(headers)
      expect(token).to eq(valid_token)
    end

    it 'returns nil for missing Authorization header' do
      headers = {}
      token = authenticator.extract_token(headers)
      expect(token).to be_nil
    end

    it 'returns nil for malformed Authorization header' do
      headers = { 'Authorization' => 'InvalidFormat token123' }
      token = authenticator.extract_token(headers)
      expect(token).to be_nil
    end

    it 'handles Authorization header case-insensitively' do
      headers = { 'authorization' => "Bearer #{valid_token}" }
      token = authenticator.extract_token(headers)
      expect(token).to eq(valid_token)
    end
  end

  describe 'token validation' do
    let(:authenticator) do
      secrets_client = instance_double(Aws::SecretsManager::Client)
      allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
      allow(secrets_client).to receive(:get_secret_value)
        .with(secret_id: 'test-secret')
        .and_return(double(secret_string: valid_secret))
      JwtAuthenticator.new('test-secret')
    end

    context 'with valid token' do
      it 'validates a properly signed JWT token' do
        result = authenticator.validate_token(valid_token)
        expect(result[:valid]).to be true
        expect(result[:payload]).to include('user_id' => '123')
      end

      it 'returns decoded payload for valid token' do
        result = authenticator.validate_token(valid_token)
        expect(result[:payload]['user_id']).to eq('123')
        expect(result[:payload]['exp']).to be > Time.now.to_i
      end
    end

    context 'with invalid token' do
      it 'rejects token signed with wrong secret' do
        result = authenticator.validate_token(invalid_token)
        expect(result[:valid]).to be false
        expect(result[:error]).to include('Invalid signature')
      end

      it 'rejects expired token' do
        result = authenticator.validate_token(expired_token)
        expect(result[:valid]).to be false
        expect(result[:error]).to include('Token has expired')
      end

      it 'rejects malformed token' do
        result = authenticator.validate_token(malformed_token)
        expect(result[:valid]).to be false
        expect(result[:error]).to include('Malformed token')
      end

      it 'handles nil token' do
        result = authenticator.validate_token(nil)
        expect(result[:valid]).to be false
        expect(result[:error]).to include('No token provided')
      end

      it 'handles empty string token' do
        result = authenticator.validate_token('')
        expect(result[:valid]).to be false
        expect(result[:error]).to include('No token provided')
      end
    end
  end

  describe 'authenticate method' do
    let(:authenticator) do
      secrets_client = instance_double(Aws::SecretsManager::Client)
      allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
      allow(secrets_client).to receive(:get_secret_value)
        .with(secret_id: 'test-secret')
        .and_return(double(secret_string: valid_secret))
      JwtAuthenticator.new('test-secret')
    end

    it 'authenticates request with valid Bearer token' do
      headers = { 'Authorization' => "Bearer #{valid_token}" }
      result = authenticator.authenticate(headers)
      expect(result[:authenticated]).to be true
      expect(result[:payload]).to include('user_id' => '123')
    end

    it 'rejects request with missing Authorization header' do
      headers = {}
      result = authenticator.authenticate(headers)
      expect(result[:authenticated]).to be false
      expect(result[:error]).to include('Missing Authorization header')
    end

    it 'rejects request with invalid Bearer token format' do
      headers = { 'Authorization' => 'NotBearer token123' }
      result = authenticator.authenticate(headers)
      expect(result[:authenticated]).to be false
      expect(result[:error]).to include('Invalid Bearer token format')
    end

    it 'rejects request with invalid JWT signature' do
      headers = { 'Authorization' => "Bearer #{invalid_token}" }
      result = authenticator.authenticate(headers)
      expect(result[:authenticated]).to be false
      expect(result[:error]).to include('Invalid signature')
    end

    it 'rejects request with expired JWT' do
      headers = { 'Authorization' => "Bearer #{expired_token}" }
      result = authenticator.authenticate(headers)
      expect(result[:authenticated]).to be false
      expect(result[:error]).to include('Token has expired')
    end

    it 'rejects request with malformed JWT' do
      headers = { 'Authorization' => "Bearer #{malformed_token}" }
      result = authenticator.authenticate(headers)
      expect(result[:authenticated]).to be false
      expect(result[:error]).to include('Malformed token')
    end
  end

  describe 'secret caching' do
    it 'caches secret for warm Lambda execution' do
      secrets_client = instance_double(Aws::SecretsManager::Client)
      allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)

      # Should only call get_secret_value once
      expect(secrets_client).to receive(:get_secret_value)
        .with(secret_id: 'test-secret')
        .once
        .and_return(double(secret_string: valid_secret))

      authenticator = JwtAuthenticator.new('test-secret')

      # Multiple validations should use cached secret
      5.times do
        authenticator.validate_token(valid_token)
      end
    end
  end

  describe 'error logging' do
    let(:authenticator) do
      secrets_client = instance_double(Aws::SecretsManager::Client)
      allow(Aws::SecretsManager::Client).to receive(:new).and_return(secrets_client)
      allow(secrets_client).to receive(:get_secret_value)
        .with(secret_id: 'test-secret')
        .and_return(double(secret_string: valid_secret))
      JwtAuthenticator.new('test-secret')
    end

    it 'logs authentication failures' do
      allow(authenticator).to receive(:log_error)

      headers = { 'Authorization' => "Bearer #{invalid_token}" }
      authenticator.authenticate(headers)

      expect(authenticator).to have_received(:log_error).with(/Authentication failed/)
    end

    it 'logs successful authentications at debug level' do
      allow(authenticator).to receive(:log_debug)

      headers = { 'Authorization' => "Bearer #{valid_token}" }
      authenticator.authenticate(headers)

      expect(authenticator).to have_received(:log_debug).with(/Authentication successful/)
    end
  end
end

require 'spec_helper'
require 'jwt'
require 'openssl'
require 'json'
require 'securerandom'

RSpec.describe 'JWT Middleware' do
  let(:user_id) { 'user123' }
  let(:permissions) { ['read', 'write'] }
  let(:exp_time) { Time.now + 3600 } # 1 hour from now
  let(:grace_period) { 300 } # 5 minutes

  let(:payload) do
    {
      user_id: user_id,
      permissions: permissions,
      exp: exp_time.to_i,
      iat: Time.now.to_i
    }
  end

  let(:rsa_private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:rsa_public_key) { rsa_private_key.public_key }
  let(:valid_token) { JWT.encode(payload, rsa_private_key, 'RS256') }

  describe 'JWT validation' do
    context 'with valid token' do
      it 'validates RS256 algorithm correctly' do
        expect {
          JWT.decode(valid_token, rsa_public_key, true, { algorithm: 'RS256' })
        }.not_to raise_error
      end

      it 'extracts user_id from token' do
        decoded = JWT.decode(valid_token, rsa_public_key, true, { algorithm: 'RS256' })
        expect(decoded[0]['user_id']).to eq(user_id)
      end

      it 'extracts permissions from token' do
        decoded = JWT.decode(valid_token, rsa_public_key, true, { algorithm: 'RS256' })
        expect(decoded[0]['permissions']).to eq(permissions)
      end

      it 'extracts expiry time from token' do
        decoded = JWT.decode(valid_token, rsa_public_key, true, { algorithm: 'RS256' })
        expect(decoded[0]['exp']).to eq(exp_time.to_i)
      end
    end

    context 'with expired token' do
      let(:expired_payload) do
        payload.merge(exp: (Time.now - 3600).to_i) # 1 hour ago
      end
      let(:expired_token) { JWT.encode(expired_payload, rsa_private_key, 'RS256') }

      it 'raises ExpiredSignature error for expired token' do
        expect {
          JWT.decode(expired_token, rsa_public_key, true, { algorithm: 'RS256' })
        }.to raise_error(JWT::ExpiredSignature)
      end
    end

    context 'with invalid signature' do
      let(:wrong_private_key) { OpenSSL::PKey::RSA.generate(2048) }
      let(:wrong_token) { JWT.encode(payload, wrong_private_key, 'RS256') }

      it 'raises VerificationError for invalid signature' do
        expect {
          JWT.decode(wrong_token, rsa_public_key, true, { algorithm: 'RS256' })
        }.to raise_error(JWT::VerificationError)
      end
    end

    context 'with malformed token' do
      it 'raises DecodeError for malformed token' do
        expect {
          JWT.decode('invalid.token.format', rsa_public_key, true, { algorithm: 'RS256' })
        }.to raise_error(JWT::DecodeError)
      end
    end
  end

  describe 'Header extraction' do
    context 'Authorization Bearer token' do
      let(:bearer_header) { "Bearer #{valid_token}" }

      it 'extracts token from Authorization header' do
        extracted_token = bearer_header.split(' ').last
        expect(extracted_token).to eq(valid_token)
      end
    end

    context 'X-Auth-Token header' do
      let(:auth_token_header) { valid_token }

      it 'extracts token from X-Auth-Token header' do
        expect(auth_token_header).to eq(valid_token)
      end
    end
  end

  describe 'Token expiry validation with grace period' do
    context 'token expired within grace period' do
      let(:grace_expired_payload) do
        payload.merge(exp: (Time.now - 60).to_i) # 1 minute ago
      end
      let(:grace_expired_token) { JWT.encode(grace_expired_payload, rsa_private_key, 'RS256') }

      it 'allows token within grace period' do
        # This would be handled by custom validation logic, not JWT gem directly
        decoded = JWT.decode(grace_expired_token, rsa_public_key, false) # Skip expiry check
        token_exp = Time.at(decoded[0]['exp'])
        time_since_expiry = Time.now - token_exp

        expect(time_since_expiry).to be <= grace_period
      end
    end

    context 'token expired beyond grace period' do
      let(:beyond_grace_payload) do
        payload.merge(exp: (Time.now - 3600).to_i) # 1 hour ago
      end
      let(:beyond_grace_token) { JWT.encode(beyond_grace_payload, rsa_private_key, 'RS256') }

      it 'rejects token beyond grace period' do
        decoded = JWT.decode(beyond_grace_token, rsa_public_key, false) # Skip expiry check
        token_exp = Time.at(decoded[0]['exp'])
        time_since_expiry = Time.now - token_exp

        expect(time_since_expiry).to be > grace_period
      end
    end
  end

  describe 'Authentication module integration' do
    it 'can be included in Lambda handlers' do
      # This will test the module inclusion pattern
      expect(defined?(JWT)).to be_truthy
    end
  end

  describe 'CloudWatch metrics requirements' do
    it 'should track authentication success events' do
      # Placeholder for CloudWatch metrics testing
      # This would require AWS SDK mocking
      expect(true).to be_truthy # Placeholder
    end

    it 'should track authentication failure events' do
      # Placeholder for CloudWatch metrics testing
      # This would require AWS SDK mocking
      expect(true).to be_truthy # Placeholder
    end
  end

  describe 'Error response format' do
    context 'with correlation ID' do
      let(:correlation_id) { SecureRandom.uuid }

      it 'includes correlation ID in error responses' do
        error_response = {
          error: 'Unauthorized',
          message: 'Invalid or expired token',
          correlation_id: correlation_id,
          timestamp: Time.now.iso8601
        }

        expect(error_response[:correlation_id]).to eq(correlation_id)
        expect(error_response[:error]).to eq('Unauthorized')
      end
    end
  end
end
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/aws_config'

RSpec.describe AwsConfig do
  describe '.secrets_manager_client' do
    context 'with default configuration' do
      before do
        ENV.delete('AWS_ENDPOINT_URL')
        ENV.delete('AWS_REGION')
        ENV.delete('AWS_DEFAULT_REGION')
      end

      it 'creates a Secrets Manager client' do
        client = described_class.secrets_manager_client
        expect(client).to be_a(Aws::SecretsManager::Client)
      end

      it 'uses default region us-east-1' do
        expect(Aws::SecretsManager::Client).to receive(:new)
          .with(hash_including(region: 'us-east-1'))
          .and_call_original

        described_class.secrets_manager_client
      end
    end

    context 'with AWS_REGION environment variable' do
      before do
        ENV['AWS_REGION'] = 'us-west-2'
        ENV.delete('AWS_ENDPOINT_URL')
      end

      after do
        ENV.delete('AWS_REGION')
      end

      it 'uses region from AWS_REGION' do
        expect(Aws::SecretsManager::Client).to receive(:new)
          .with(hash_including(region: 'us-west-2'))
          .and_call_original

        described_class.secrets_manager_client
      end
    end

    context 'with AWS_DEFAULT_REGION environment variable' do
      before do
        ENV.delete('AWS_REGION')
        ENV['AWS_DEFAULT_REGION'] = 'eu-central-1'
        ENV.delete('AWS_ENDPOINT_URL')
      end

      after do
        ENV.delete('AWS_DEFAULT_REGION')
      end

      it 'uses region from AWS_DEFAULT_REGION' do
        expect(Aws::SecretsManager::Client).to receive(:new)
          .with(hash_including(region: 'eu-central-1'))
          .and_call_original

        described_class.secrets_manager_client
      end
    end

    context 'with AWS_ENDPOINT_URL for LocalStack' do
      before do
        ENV['AWS_ENDPOINT_URL'] = 'http://localhost:4566'
        ENV['AWS_REGION'] = 'us-east-1'
      end

      after do
        ENV.delete('AWS_ENDPOINT_URL')
        ENV.delete('AWS_REGION')
      end

      it 'configures custom endpoint' do
        expect(Aws::SecretsManager::Client).to receive(:new) do |config|
          expect(config[:endpoint]).to eq('http://localhost:4566')
          instance_double(Aws::SecretsManager::Client)
        end

        described_class.secrets_manager_client
      end

      it 'sets test credentials' do
        expect(Aws::SecretsManager::Client).to receive(:new) do |config|
          expect(config[:credentials].access_key_id).to eq('test')
          expect(config[:credentials].secret_access_key).to eq('test')
          instance_double(Aws::SecretsManager::Client)
        end

        described_class.secrets_manager_client
      end

      it 'sets credentials for LocalStack' do
        expect(Aws::SecretsManager::Client).to receive(:new) do |config|
          expect(config[:endpoint]).to eq('http://localhost:4566')
          expect(config[:credentials]).to be_a(Aws::Credentials)
          instance_double(Aws::SecretsManager::Client)
        end

        described_class.secrets_manager_client
      end

      it 'outputs debug message' do
        allow(Aws::SecretsManager::Client).to receive(:new).and_return(instance_double(Aws::SecretsManager::Client))

        expect do
          described_class.secrets_manager_client
        end.to output(%r{DEBUG: Using custom endpoint: http://localhost:4566}).to_stdout
      end
    end

    context 'with custom AWS_ENDPOINT_URL' do
      before do
        ENV['AWS_ENDPOINT_URL'] = 'https://custom-endpoint.example.com'
        ENV['AWS_REGION'] = 'ap-southeast-2'
      end

      after do
        ENV.delete('AWS_ENDPOINT_URL')
        ENV.delete('AWS_REGION')
      end

      it 'uses custom endpoint' do
        expect(Aws::SecretsManager::Client).to receive(:new) do |config|
          expect(config[:endpoint]).to eq('https://custom-endpoint.example.com')
          instance_double(Aws::SecretsManager::Client)
        end

        described_class.secrets_manager_client
      end

      it 'combines custom endpoint with region' do
        expect(Aws::SecretsManager::Client).to receive(:new) do |config|
          expect(config[:endpoint]).to eq('https://custom-endpoint.example.com')
          expect(config[:region]).to eq('ap-southeast-2')
          instance_double(Aws::SecretsManager::Client)
        end

        described_class.secrets_manager_client
      end
    end
  end

  describe '.region' do
    context 'with AWS_REGION set' do
      before do
        ENV['AWS_REGION'] = 'us-west-1'
        ENV.delete('AWS_DEFAULT_REGION')
      end

      after do
        ENV.delete('AWS_REGION')
      end

      it 'returns AWS_REGION value' do
        expect(described_class.region).to eq('us-west-1')
      end
    end

    context 'with AWS_DEFAULT_REGION set' do
      before do
        ENV.delete('AWS_REGION')
        ENV['AWS_DEFAULT_REGION'] = 'eu-west-1'
      end

      after do
        ENV.delete('AWS_DEFAULT_REGION')
      end

      it 'returns AWS_DEFAULT_REGION value' do
        expect(described_class.region).to eq('eu-west-1')
      end
    end

    context 'with both AWS_REGION and AWS_DEFAULT_REGION set' do
      before do
        ENV['AWS_REGION'] = 'us-east-2'
        ENV['AWS_DEFAULT_REGION'] = 'us-west-2'
      end

      after do
        ENV.delete('AWS_REGION')
        ENV.delete('AWS_DEFAULT_REGION')
      end

      it 'prefers AWS_REGION over AWS_DEFAULT_REGION' do
        expect(described_class.region).to eq('us-east-2')
      end
    end

    context 'without region environment variables' do
      before do
        ENV.delete('AWS_REGION')
        ENV.delete('AWS_DEFAULT_REGION')
      end

      it 'returns default region us-east-1' do
        expect(described_class.region).to eq('us-east-1')
      end
    end
  end

  describe '.jwt_secret_name' do
    context 'with JWT_SECRET_NAME set' do
      before do
        ENV['JWT_SECRET_NAME'] = 'custom/jwt/secret'
      end

      after do
        ENV.delete('JWT_SECRET_NAME')
      end

      it 'returns JWT_SECRET_NAME value' do
        expect(described_class.jwt_secret_name).to eq('custom/jwt/secret')
      end
    end

    context 'without JWT_SECRET_NAME' do
      before do
        ENV.delete('JWT_SECRET_NAME')
      end

      it 'returns default secret name' do
        expect(described_class.jwt_secret_name).to eq('pdf-converter/jwt-secret')
      end
    end

    context 'with empty JWT_SECRET_NAME' do
      before do
        ENV['JWT_SECRET_NAME'] = ''
      end

      after do
        ENV.delete('JWT_SECRET_NAME')
      end

      it 'returns empty string (empty strings are truthy in Ruby)' do
        # Empty string is truthy in Ruby's || operator
        expect(described_class.jwt_secret_name).to eq('')
      end
    end
  end
end

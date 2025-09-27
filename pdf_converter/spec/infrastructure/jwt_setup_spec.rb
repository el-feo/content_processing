require 'spec_helper'

RSpec.describe 'JWT Infrastructure Setup' do
  describe 'gem dependencies' do
    it 'has jwt gem available' do
      expect { require 'jwt' }.not_to raise_error
    end

    it 'has aws-sdk-secretsmanager gem available' do
      expect { require 'aws-sdk-secretsmanager' }.not_to raise_error
    end

    it 'loads JWT with correct version' do
      require 'jwt'
      jwt_version = Gem.loaded_specs['jwt'].version.to_s
      expect(Gem::Version.new(jwt_version)).to be >= Gem::Version.new('2.7.0')
    end
  end

  describe 'AWS configuration' do
    it 'has AWS region environment variable defined' do
      expect(ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION']).not_to be_nil
    end

    it 'has JWT secret name environment variable defined' do
      expect(ENV['JWT_SECRET_NAME']).not_to be_nil
    end
  end

  describe 'AWS SDK initialization' do
    it 'can initialize AWS Secrets Manager client' do
      require 'aws-sdk-secretsmanager'
      expect { Aws::SecretsManager::Client.new(region: 'us-east-1') }.not_to raise_error
    end
  end
end
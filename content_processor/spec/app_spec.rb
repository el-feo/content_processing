require 'spec_helper'
require_relative '../app'

RSpec.describe 'Content Processor Lambda' do
  describe '.lambda_handler' do
    let(:context) { {} }

    context 'without authentication' do
      let(:event) do
        {
          'httpMethod' => 'GET',
          'path' => '/process'
        }
      end

      it 'returns unauthorized response' do
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(401)
        expect(response[:body]).to be_a(String)
        parsed_body = JSON.parse(response[:body])
        expect(parsed_body).to have_key('error')
        expect(parsed_body['error']).to eq('Unauthorized')
      end
    end

    context 'with missing JWT public key' do
      let(:event) do
        {
          'httpMethod' => 'GET',
          'path' => '/process',
          'headers' => {
            'Authorization' => 'Bearer invalid.token.here'
          }
        }
      end

      it 'returns error for missing JWT configuration' do
        response = lambda_handler(event: event, context: context)

        expect(response[:statusCode]).to eq(401)
        expect(response[:body]).to be_a(String)
        parsed_body = JSON.parse(response[:body])
        expect(parsed_body).to have_key('error')
        expect(parsed_body['message']).to include('JWT public key not configured')
      end
    end
  end
end
require 'spec_helper'
require_relative '../app'

RSpec.describe 'Content Processor Lambda' do
  describe '.lambda_handler' do
    let(:event) do
      {
        'httpMethod' => 'GET',
        'path' => '/process'
      }
    end

    let(:context) { {} }

    it 'returns a successful response' do
      response = lambda_handler(event: event, context: context)

      expect(response[:statusCode]).to eq(200)
      expect(response[:body]).to be_a(String)
      expect(JSON.parse(response[:body])).to have_key('message')
    end

    it 'returns a valid JSON body' do
      response = lambda_handler(event: event, context: context)

      expect { JSON.parse(response[:body]) }.not_to raise_error
      expect(JSON.parse(response[:body])).to include('message' => 'Content processed successfully')
    end
  end
end
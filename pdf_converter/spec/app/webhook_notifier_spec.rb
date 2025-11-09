# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require_relative '../../app/webhook_notifier'

RSpec.describe WebhookNotifier do
  let(:notifier) { described_class.new }
  let(:webhook_url) { 'https://example.com/webhook' }
  let(:params) do
    {
      webhook_url: webhook_url,
      unique_id: 'test-123',
      status: 'completed',
      images: ['https://s3.amazonaws.com/bucket/page-1.png'],
      page_count: 1,
      processing_time_ms: 1500
    }
  end

  before do
    WebMock.disable_net_connect!
  end

  after do
    WebMock.reset!
  end

  describe 'DEFAULT_TIMEOUT' do
    it 'is set to 10 seconds' do
      expect(WebhookNotifier::DEFAULT_TIMEOUT).to eq(10)
    end
  end

  describe '#notify' do
    context 'with successful webhook delivery' do
      before do
        stub_request(:post, webhook_url)
          .to_return(status: 200, body: '', headers: {})
      end

      it 'returns success' do
        result = notifier.notify(**params)
        expect(result[:success]).to be true
      end

      it 'sends POST request to webhook URL' do
        notifier.notify(**params)
        expect(WebMock).to have_requested(:post, webhook_url).once
      end

      it 'sends correct JSON payload' do
        notifier.notify(**params)

        expect(WebMock).to(have_requested(:post, webhook_url).with do |req|
          body = JSON.parse(req.body)
          body['unique_id'] == 'test-123' &&
            body['status'] == 'completed' &&
            body['page_count'] == 1 &&
            body['processing_time_ms'] == 1500
        end)
      end

      it 'sends Content-Type header' do
        notifier.notify(**params)

        expect(WebMock).to have_requested(:post, webhook_url)
          .with(headers: { 'Content-Type' => 'application/json' })
      end

      it 'includes images array in payload' do
        notifier.notify(**params)

        expect(WebMock).to(have_requested(:post, webhook_url).with do |req|
          body = JSON.parse(req.body)
          body['images'] == ['https://s3.amazonaws.com/bucket/page-1.png']
        end)
      end

      it 'outputs success message' do
        expect { notifier.notify(**params) }
          .to output(/Webhook notification sent successfully/).to_stdout
      end
    end

    context 'with HTTP success codes' do
      [200, 201, 202, 204].each do |status_code|
        context "when webhook returns #{status_code}" do
          before do
            stub_request(:post, webhook_url)
              .to_return(status: status_code, body: '', headers: {})
          end

          it 'treats as success' do
            result = notifier.notify(**params)
            expect(result[:success]).to be true
          end
        end
      end
    end

    context 'with HTTP error responses' do
      context 'when webhook returns 400' do
        before do
          stub_request(:post, webhook_url)
            .to_return(status: 400, body: 'Bad Request', headers: {})
        end

        it 'returns error with status code' do
          result = notifier.notify(**params)
          expect(result[:error]).to include('HTTP 400')
        end

        it 'includes error message' do
          result = notifier.notify(**params)
          expect(result[:error]).to include('Bad Request')
        end
      end

      context 'when webhook returns 404' do
        before do
          stub_request(:post, webhook_url)
            .to_return(status: 404, body: 'Not Found', headers: {})
        end

        it 'returns error with status code' do
          result = notifier.notify(**params)
          expect(result[:error]).to include('HTTP 404')
        end
      end

      context 'when webhook returns 500' do
        before do
          stub_request(:post, webhook_url)
            .to_return(status: 500, body: 'Internal Server Error', headers: {})
        end

        it 'returns error with status code' do
          result = notifier.notify(**params)
          expect(result[:error]).to include('HTTP 500')
        end
      end
    end

    context 'with HTTP redirects' do
      context 'when webhook returns 301' do
        before do
          stub_request(:post, webhook_url)
            .to_return(status: 301, body: '', headers: {})
        end

        it 'treats redirect as non-success' do
          result = notifier.notify(**params)
          expect(result[:error]).to include('HTTP 301')
        end
      end
    end

    context 'with network errors' do
      context 'when connection times out' do
        before do
          stub_request(:post, webhook_url).to_timeout
        end

        it 'returns error with timeout message' do
          result = notifier.notify(**params)
          expect(result[:error]).to include('Webhook error')
          expect(result[:error]).to include('execution expired')
        end
      end

      context 'when connection is refused' do
        before do
          stub_request(:post, webhook_url).to_raise(Errno::ECONNREFUSED)
        end

        it 'returns error with connection refused message' do
          result = notifier.notify(**params)
          expect(result[:error]).to include('Webhook error')
          expect(result[:error]).to include('Connection refused')
        end
      end

      context 'when DNS resolution fails' do
        before do
          stub_request(:post, webhook_url).to_raise(SocketError.new('getaddrinfo failed'))
        end

        it 'returns error with DNS error message' do
          result = notifier.notify(**params)
          expect(result[:error]).to include('Webhook error')
          expect(result[:error]).to include('getaddrinfo')
        end
      end

      context 'when SSL verification fails' do
        before do
          stub_request(:post, webhook_url).to_raise(OpenSSL::SSL::SSLError.new('SSL verification failed'))
        end

        it 'returns error with SSL error message' do
          result = notifier.notify(**params)
          expect(result[:error]).to include('Webhook error')
          expect(result[:error]).to include('SSL')
        end
      end
    end

    context 'with invalid webhook URL' do
      let(:params) do
        super().merge(webhook_url: 'not a valid url')
      end

      it 'returns error for invalid URI' do
        result = notifier.notify(**params)
        expect(result[:error]).to include('Webhook error')
      end
    end

    context 'with HTTP webhook (not HTTPS)' do
      let(:webhook_url) { 'http://example.com/webhook' }

      before do
        stub_request(:post, webhook_url)
          .to_return(status: 200, body: '', headers: {})
      end

      it 'successfully sends to HTTP URL' do
        result = notifier.notify(**params)
        expect(result[:success]).to be true
      end

      it 'does not use SSL for HTTP' do
        notifier.notify(**params)
        expect(WebMock).to have_requested(:post, webhook_url)
      end
    end

    context 'with HTTPS webhook' do
      let(:webhook_url) { 'https://secure.example.com/webhook' }

      before do
        stub_request(:post, webhook_url)
          .to_return(status: 200, body: '', headers: {})
      end

      it 'successfully sends to HTTPS URL' do
        result = notifier.notify(**params)
        expect(result[:success]).to be true
      end

      it 'uses SSL for HTTPS' do
        notifier.notify(**params)
        expect(WebMock).to have_requested(:post, webhook_url)
      end
    end

    context 'with multiple images' do
      let(:params) do
        super().merge(
          images: [
            'https://s3.amazonaws.com/bucket/page-1.png',
            'https://s3.amazonaws.com/bucket/page-2.png',
            'https://s3.amazonaws.com/bucket/page-3.png'
          ],
          page_count: 3
        )
      end

      before do
        stub_request(:post, webhook_url)
          .to_return(status: 200, body: '', headers: {})
      end

      it 'includes all images in payload' do
        notifier.notify(**params)

        expect(WebMock).to(have_requested(:post, webhook_url).with do |req|
          body = JSON.parse(req.body)
          body['images'].size == 3 && body['page_count'] == 3
        end)
      end
    end

    context 'with empty images array' do
      let(:params) do
        super().merge(images: [], page_count: 0)
      end

      before do
        stub_request(:post, webhook_url)
          .to_return(status: 200, body: '', headers: {})
      end

      it 'sends empty images array' do
        notifier.notify(**params)

        expect(WebMock).to(have_requested(:post, webhook_url).with do |req|
          body = JSON.parse(req.body)
          body['images'] == [] && body['page_count'] == 0
        end)
      end
    end

    context 'with long processing time' do
      let(:params) do
        super().merge(processing_time_ms: 60_000)
      end

      before do
        stub_request(:post, webhook_url)
          .to_return(status: 200, body: '', headers: {})
      end

      it 'includes processing time in payload' do
        notifier.notify(**params)

        expect(WebMock).to(have_requested(:post, webhook_url).with do |req|
          body = JSON.parse(req.body)
          body['processing_time_ms'] == 60_000
        end)
      end
    end

    context 'with special characters in unique_id' do
      let(:params) do
        super().merge(unique_id: 'test-id_123')
      end

      before do
        stub_request(:post, webhook_url)
          .to_return(status: 200, body: '', headers: {})
      end

      it 'properly encodes unique_id in JSON' do
        notifier.notify(**params)

        expect(WebMock).to(have_requested(:post, webhook_url).with do |req|
          body = JSON.parse(req.body)
          body['unique_id'] == 'test-id_123'
        end)
      end
    end

    context 'payload structure' do
      before do
        stub_request(:post, webhook_url)
          .to_return(status: 200, body: '', headers: {})
      end

      it 'includes all required fields' do
        notifier.notify(**params)

        expect(WebMock).to(have_requested(:post, webhook_url).with do |req|
          body = JSON.parse(req.body)
          body.keys.sort == %w[images page_count processing_time_ms status unique_id].sort
        end)
      end
    end
  end

  describe 'private methods' do
    describe '#build_payload' do
      it 'is private' do
        expect(notifier.private_methods).to include(:build_payload)
      end
    end

    describe '#send_request' do
      it 'is private' do
        expect(notifier.private_methods).to include(:send_request)
      end
    end
  end
end

# frozen_string_literal: true

require 'logger'
require_relative '../spec_helper'
require_relative '../../lib/retry_handler'

RSpec.describe RetryHandler do
  describe '.with_retry' do
    context 'when operation succeeds on first attempt' do
      it 'returns the result without retrying' do
        result = described_class.with_retry do |attempt|
          expect(attempt).to eq(1)
          'success'
        end

        expect(result).to eq('success')
      end
    end

    context 'when operation succeeds after retries' do
      it 'retries and returns the result' do
        call_count = 0

        result = described_class.with_retry(max_attempts: 3) do |attempt|
          call_count += 1

          raise Timeout::Error, 'Timeout' if attempt < 3

          'success'
        end

        expect(result).to eq('success')
        expect(call_count).to eq(3)
      end
    end

    context 'when all retry attempts are exhausted' do
      it 'raises RetryError with the last error message' do
        expect do
          described_class.with_retry(max_attempts: 3) do
            raise Timeout::Error, 'Connection timeout'
          end
        end.to raise_error(RetryHandler::RetryError, /Connection timeout after 3 attempts/)
      end
    end

    context 'with retryable exceptions' do
      it 'retries Timeout::Error' do
        call_count = 0

        described_class.with_retry(max_attempts: 2) do |attempt|
          call_count += 1
          raise Timeout::Error, 'Timeout' if attempt == 1

          'success'
        end

        expect(call_count).to eq(2)
      end

      it 'retries Errno::ECONNREFUSED' do
        call_count = 0

        described_class.with_retry(max_attempts: 2) do |attempt|
          call_count += 1
          raise Errno::ECONNREFUSED, 'Connection refused' if attempt == 1

          'success'
        end

        expect(call_count).to eq(2)
      end

      it 'retries SocketError' do
        call_count = 0

        described_class.with_retry(max_attempts: 2) do |attempt|
          call_count += 1
          raise SocketError, 'DNS error' if attempt == 1

          'success'
        end

        expect(call_count).to eq(2)
      end

      it 'retries OpenSSL::SSL::SSLError' do
        call_count = 0

        described_class.with_retry(max_attempts: 2) do |attempt|
          call_count += 1
          raise OpenSSL::SSL::SSLError, 'SSL error' if attempt == 1

          'success'
        end

        expect(call_count).to eq(2)
      end

      it 'retries retryable HTTP status codes (500, 502, 503, 504)' do
        [500, 502, 503, 504].each do |status_code|
          call_count = 0

          described_class.with_retry(max_attempts: 2) do |attempt|
            call_count += 1
            raise StandardError, "HTTP #{status_code}: Server Error" if attempt == 1

            'success'
          end

          expect(call_count).to eq(2)
        end
      end
    end

    context 'with non-retryable exceptions' do
      it 'does not retry NoMemoryError' do
        call_count = 0

        expect do
          described_class.with_retry(max_attempts: 3) do
            call_count += 1
            raise NoMemoryError, 'Out of memory'
          end
        end.to raise_error(NoMemoryError, 'Out of memory')

        expect(call_count).to eq(1)
      end

      it 'does not retry non-retryable HTTP status codes (400, 404, 403)' do
        [400, 404, 403].each do |status_code|
          call_count = 0

          expect do
            described_class.with_retry(max_attempts: 3) do
              call_count += 1
              raise StandardError, "HTTP #{status_code}: Client Error"
            end
          end.to raise_error(StandardError, /HTTP #{status_code}/)

          expect(call_count).to eq(1)
        end
      end

      it 'does not retry ArgumentError' do
        call_count = 0

        expect do
          described_class.with_retry(max_attempts: 3) do
            call_count += 1
            raise ArgumentError, 'Invalid argument'
          end
        end.to raise_error(ArgumentError, 'Invalid argument')

        expect(call_count).to eq(1)
      end
    end

    context 'with exponential backoff' do
      it 'waits with exponential backoff between retries' do
        described_class.with_retry(max_attempts: 3, delay_base: 1) do |attempt|
          if attempt < 3
            Time.now
            raise Timeout::Error, 'Timeout'
          end

          'success'
        end

        # NOTE: We can't easily test the actual sleep times without mocking,
        # but we can verify the calculation in a separate test
      end
    end

    context 'with custom retry configuration' do
      it 'uses custom max_attempts' do
        call_count = 0

        expect do
          described_class.with_retry(max_attempts: 5) do
            call_count += 1
            raise Timeout::Error, 'Timeout'
          end
        end.to raise_error(RetryHandler::RetryError, /after 5 attempts/)

        expect(call_count).to eq(5)
      end

      it 'uses custom delay_base' do
        # Testing delay_base would require mocking sleep, which we can verify through wait_before_retry method
      end
    end

    context 'with logger' do
      it 'logs retry attempts when logger is provided' do
        logger = instance_double(Logger)
        allow(logger).to receive(:info)

        described_class.with_retry(max_attempts: 2, logger: logger) do |attempt|
          raise Timeout::Error, 'Timeout' if attempt == 1

          'success'
        end

        expect(logger).to have_received(:info).with(/Retrying attempt 2 after error: Timeout/)
      end

      it 'outputs to stdout when logger is nil' do
        expect do
          described_class.with_retry(max_attempts: 2, logger: nil) do |attempt|
            raise Timeout::Error, 'Timeout' if attempt == 1

            'success'
          end
        end.to output(/Retrying attempt 2/).to_stdout
      end
    end
  end

  describe '.retryable_error?' do
    it 'returns true for Timeout::Error' do
      error = Timeout::Error.new('Timeout')
      expect(described_class.retryable_error?(error)).to be true
    end

    it 'returns true for Errno::ECONNREFUSED' do
      error = Errno::ECONNREFUSED.new('Connection refused')
      expect(described_class.retryable_error?(error)).to be true
    end

    it 'returns true for SocketError' do
      error = SocketError.new('DNS error')
      expect(described_class.retryable_error?(error)).to be true
    end

    it 'returns true for OpenSSL::SSL::SSLError' do
      error = OpenSSL::SSL::SSLError.new('SSL error')
      expect(described_class.retryable_error?(error)).to be true
    end

    it 'returns true for retryable HTTP status codes' do
      [500, 502, 503, 504].each do |status_code|
        error = StandardError.new("HTTP #{status_code}: Server Error")
        expect(described_class.retryable_error?(error)).to be true
      end
    end

    it 'returns false for non-retryable HTTP status codes' do
      [400, 403, 404].each do |status_code|
        error = StandardError.new("HTTP #{status_code}: Client Error")
        expect(described_class.retryable_error?(error)).to be false
      end
    end

    it 'returns false for generic StandardError' do
      error = StandardError.new('Generic error')
      expect(described_class.retryable_error?(error)).to be false
    end
  end

  describe '.wait_before_retry' do
    it 'calculates exponential backoff correctly' do
      # Mock sleep to verify correct delays
      allow(described_class).to receive(:sleep)

      described_class.wait_before_retry(1, 1)
      expect(described_class).to have_received(:sleep).with(1) # 1 * 2^0 = 1

      described_class.wait_before_retry(2, 1)
      expect(described_class).to have_received(:sleep).with(2) # 1 * 2^1 = 2

      described_class.wait_before_retry(3, 1)
      expect(described_class).to have_received(:sleep).with(4) # 1 * 2^2 = 4
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require_relative '../../lib/retry_handler'

RSpec.describe RetryHandler do
  let(:logger) { instance_double(Logger).as_null_object }

  describe '.with_retry' do
    context 'when block succeeds on first attempt' do
      it 'returns the block result' do
        result = described_class.with_retry { 'success' }
        expect(result).to eq('success')
      end

      it 'yields attempt number to block' do
        described_class.with_retry do |attempt|
          expect(attempt).to eq(1)
          'done'
        end
      end

      it 'does not sleep' do
        expect(described_class).not_to receive(:wait_before_retry)
        described_class.with_retry { 'success' }
      end
    end

    context 'when block succeeds after retries' do
      it 'retries on Timeout::Error and eventually succeeds' do
        call_count = 0
        result = described_class.with_retry(max_attempts: 3) do
          call_count += 1
          raise Timeout::Error if call_count < 3

          'success'
        end

        expect(result).to eq('success')
        expect(call_count).to eq(3)
      end

      it 'retries on SocketError' do
        call_count = 0
        result = described_class.with_retry(max_attempts: 3) do
          call_count += 1
          raise SocketError if call_count < 2

          'success'
        end

        expect(result).to eq('success')
        expect(call_count).to eq(2)
      end

      it 'retries on Errno::ECONNREFUSED' do
        call_count = 0
        result = described_class.with_retry(max_attempts: 3) do
          call_count += 1
          raise Errno::ECONNREFUSED if call_count < 2

          'success'
        end

        expect(result).to eq('success')
        expect(call_count).to eq(2)
      end

      it 'retries on OpenSSL::SSL::SSLError' do
        call_count = 0
        result = described_class.with_retry(max_attempts: 3) do
          call_count += 1
          raise OpenSSL::SSL::SSLError if call_count < 2

          'success'
        end

        expect(result).to eq('success')
        expect(call_count).to eq(2)
      end

      it 'retries on HTTP 500 error' do
        call_count = 0
        result = described_class.with_retry(max_attempts: 3) do
          call_count += 1
          raise StandardError, 'HTTP 500: Internal Server Error' if call_count < 2

          'success'
        end

        expect(result).to eq('success')
        expect(call_count).to eq(2)
      end

      it 'retries on HTTP 502 error' do
        call_count = 0
        result = described_class.with_retry(max_attempts: 3) do
          call_count += 1
          raise StandardError, 'HTTP 502: Bad Gateway' if call_count < 2

          'success'
        end

        expect(result).to eq('success')
      end

      it 'retries on HTTP 503 error' do
        call_count = 0
        result = described_class.with_retry(max_attempts: 3) do
          call_count += 1
          raise StandardError, 'HTTP 503: Service Unavailable' if call_count < 2

          'success'
        end

        expect(result).to eq('success')
      end

      it 'retries on HTTP 504 error' do
        call_count = 0
        result = described_class.with_retry(max_attempts: 3) do
          call_count += 1
          raise StandardError, 'HTTP 504: Gateway Timeout' if call_count < 2

          'success'
        end

        expect(result).to eq('success')
      end

      it 'waits with exponential backoff between retries' do
        allow(described_class).to receive(:sleep)

        call_count = 0
        described_class.with_retry(max_attempts: 4, delay_base: 1) do
          call_count += 1
          raise Timeout::Error if call_count < 4

          'success'
        end

        # Should sleep 1s (2^0), 2s (2^1), 4s (2^2)
        expect(described_class).to have_received(:sleep).with(1).once
        expect(described_class).to have_received(:sleep).with(2).once
        expect(described_class).to have_received(:sleep).with(4).once
      end

      it 'logs retry attempts with logger' do
        call_count = 0
        described_class.with_retry(max_attempts: 3, logger: logger) do
          call_count += 1
          raise Timeout::Error, 'Connection timeout' if call_count < 3

          'success'
        end

        expect(logger).to have_received(:info).twice
      end
    end

    context 'when all retry attempts are exhausted' do
      it 'raises RetryError after max attempts' do
        expect do
          described_class.with_retry(max_attempts: 3) do
            raise Timeout::Error, 'Always fails'
          end
        end.to raise_error(RetryHandler::RetryError, /Always fails after 3 attempts/)
      end

      it 'attempts exactly max_attempts times' do
        call_count = 0
        expect do
          described_class.with_retry(max_attempts: 3) do
            call_count += 1
            raise Timeout::Error
          end
        end.to raise_error(RetryHandler::RetryError)

        expect(call_count).to eq(3)
      end

      it 'includes error message in RetryError' do
        expect do
          described_class.with_retry(max_attempts: 2) do
            raise SocketError, 'Connection refused'
          end
        end.to raise_error(RetryHandler::RetryError, /Connection refused after 2 attempts/)
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
        end.to raise_error(NoMemoryError, /Out of memory/)

        expect(call_count).to eq(1)
      end

      it 'raises non-retryable error immediately' do
        expect(described_class).not_to receive(:wait_before_retry)

        expect do
          described_class.with_retry(max_attempts: 3) do
            raise NoMemoryError
          end
        end.to raise_error(NoMemoryError)
      end
    end

    context 'with non-retryable errors' do
      it 'does not retry HTTP 400 error' do
        call_count = 0
        expect do
          described_class.with_retry(max_attempts: 3) do
            call_count += 1
            raise StandardError, 'HTTP 400: Bad Request'
          end
        end.to raise_error(StandardError, /HTTP 400/)

        expect(call_count).to eq(1)
      end

      it 'does not retry HTTP 404 error' do
        call_count = 0
        expect do
          described_class.with_retry(max_attempts: 3) do
            call_count += 1
            raise StandardError, 'HTTP 404: Not Found'
          end
        end.to raise_error(StandardError, /HTTP 404/)

        expect(call_count).to eq(1)
      end

      it 'does not retry generic StandardError' do
        call_count = 0
        expect do
          described_class.with_retry(max_attempts: 3) do
            call_count += 1
            raise StandardError, 'Generic error'
          end
        end.to raise_error(StandardError, /Generic error/)

        expect(call_count).to eq(1)
      end
    end

    context 'with custom configuration' do
      it 'respects custom max_attempts' do
        call_count = 0
        expect do
          described_class.with_retry(max_attempts: 5) do
            call_count += 1
            raise Timeout::Error
          end
        end.to raise_error(RetryHandler::RetryError, /after 5 attempts/)

        expect(call_count).to eq(5)
      end

      it 'uses custom delay_base for backoff' do
        allow(described_class).to receive(:sleep)

        call_count = 0
        described_class.with_retry(max_attempts: 3, delay_base: 2) do
          call_count += 1
          raise Timeout::Error if call_count < 3

          'success'
        end

        # With delay_base=2: 2s (2*2^0), 4s (2*2^1)
        expect(described_class).to have_received(:sleep).with(2).once
        expect(described_class).to have_received(:sleep).with(4).once
      end

      it 'logs to provided logger' do
        described_class.with_retry(max_attempts: 2, logger: logger) do |attempt|
          raise Timeout::Error if attempt == 1

          'success'
        end

        expect(logger).to have_received(:info).once
      end
    end

    context 'without logger' do
      it 'logs to stdout when no logger provided' do
        call_count = 0
        expect do
          described_class.with_retry(max_attempts: 2) do
            call_count += 1
            raise Timeout::Error if call_count < 2

            'success'
          end
        end.to output(/INFO: Retrying attempt/).to_stdout
      end
    end
  end

  describe '.retryable_error?' do
    context 'with retryable exception types' do
      it 'returns true for Timeout::Error' do
        error = Timeout::Error.new('timeout')
        expect(described_class.retryable_error?(error)).to be true
      end

      it 'returns true for Errno::ECONNREFUSED' do
        error = Errno::ECONNREFUSED.new('connection refused')
        expect(described_class.retryable_error?(error)).to be true
      end

      it 'returns true for SocketError' do
        error = SocketError.new('socket error')
        expect(described_class.retryable_error?(error)).to be true
      end

      it 'returns true for OpenSSL::SSL::SSLError' do
        error = OpenSSL::SSL::SSLError.new('ssl error')
        expect(described_class.retryable_error?(error)).to be true
      end
    end

    context 'with retryable HTTP status codes' do
      it 'returns true for HTTP 500' do
        error = StandardError.new('HTTP 500: Internal Server Error')
        expect(described_class.retryable_error?(error)).to be true
      end

      it 'returns true for HTTP 502' do
        error = StandardError.new('HTTP 502: Bad Gateway')
        expect(described_class.retryable_error?(error)).to be true
      end

      it 'returns true for HTTP 503' do
        error = StandardError.new('HTTP 503: Service Unavailable')
        expect(described_class.retryable_error?(error)).to be true
      end

      it 'returns true for HTTP 504' do
        error = StandardError.new('HTTP 504: Gateway Timeout')
        expect(described_class.retryable_error?(error)).to be true
      end

      it 'extracts status code from error message' do
        error = StandardError.new('Failed with HTTP 503: temporarily unavailable')
        expect(described_class.retryable_error?(error)).to be true
      end
    end

    context 'with non-retryable errors' do
      it 'returns false for HTTP 400' do
        error = StandardError.new('HTTP 400: Bad Request')
        expect(described_class.retryable_error?(error)).to be false
      end

      it 'returns false for HTTP 404' do
        error = StandardError.new('HTTP 404: Not Found')
        expect(described_class.retryable_error?(error)).to be false
      end

      it 'returns false for HTTP 401' do
        error = StandardError.new('HTTP 401: Unauthorized')
        expect(described_class.retryable_error?(error)).to be false
      end

      it 'returns false for generic StandardError' do
        error = StandardError.new('Some other error')
        expect(described_class.retryable_error?(error)).to be false
      end

      it 'returns false for NoMemoryError' do
        error = NoMemoryError.new('out of memory')
        expect(described_class.retryable_error?(error)).to be false
      end

      it 'returns false for ArgumentError' do
        error = ArgumentError.new('invalid argument')
        expect(described_class.retryable_error?(error)).to be false
      end
    end
  end

  describe '.wait_before_retry' do
    it 'calculates exponential backoff correctly for attempt 1' do
      expect(described_class).to receive(:sleep).with(1) # 1 * 2^0 = 1
      described_class.wait_before_retry(1, 1)
    end

    it 'calculates exponential backoff correctly for attempt 2' do
      expect(described_class).to receive(:sleep).with(2) # 1 * 2^1 = 2
      described_class.wait_before_retry(2, 1)
    end

    it 'calculates exponential backoff correctly for attempt 3' do
      expect(described_class).to receive(:sleep).with(4) # 1 * 2^2 = 4
      described_class.wait_before_retry(3, 1)
    end

    it 'calculates exponential backoff correctly for attempt 4' do
      expect(described_class).to receive(:sleep).with(8) # 1 * 2^3 = 8
      described_class.wait_before_retry(4, 1)
    end

    it 'uses custom delay_base in calculation' do
      expect(described_class).to receive(:sleep).with(6) # 3 * 2^1 = 6
      described_class.wait_before_retry(2, 3)
    end
  end

  describe '.log_retry' do
    context 'with logger provided' do
      it 'logs to the logger' do
        described_class.log_retry(logger, 1, 'Test error')
        expect(logger).to have_received(:info)
          .with('Retrying attempt 2 after error: Test error')
      end

      it 'includes attempt number in log message' do
        described_class.log_retry(logger, 3, 'Connection timeout')
        expect(logger).to have_received(:info)
          .with('Retrying attempt 4 after error: Connection timeout')
      end
    end

    context 'without logger' do
      it 'logs to stdout' do
        expect do
          described_class.log_retry(nil, 1, 'Network error')
        end.to output("INFO: Retrying attempt 2 after error: Network error\n").to_stdout
      end

      it 'formats message correctly' do
        expect do
          described_class.log_retry(nil, 2, 'Timeout occurred')
        end.to output(/Retrying attempt 3 after error: Timeout occurred/).to_stdout
      end
    end
  end

  describe 'RetryError' do
    it 'is a subclass of StandardError' do
      expect(RetryHandler::RetryError).to be < StandardError
    end

    it 'can be raised with a message' do
      expect do
        raise RetryHandler::RetryError, 'Custom retry error'
      end.to raise_error(RetryHandler::RetryError, 'Custom retry error')
    end
  end

  describe 'constants' do
    it 'defines DEFAULT_MAX_ATTEMPTS' do
      expect(RetryHandler::DEFAULT_MAX_ATTEMPTS).to eq(3)
    end

    it 'defines DEFAULT_RETRY_DELAY_BASE' do
      expect(RetryHandler::DEFAULT_RETRY_DELAY_BASE).to eq(1)
    end

    it 'defines RETRYABLE_HTTP_CODES' do
      expect(RetryHandler::RETRYABLE_HTTP_CODES).to eq([500, 502, 503, 504])
    end

    it 'defines RETRYABLE_EXCEPTIONS' do
      expect(RetryHandler::RETRYABLE_EXCEPTIONS).to include(
        Timeout::Error,
        Errno::ECONNREFUSED,
        SocketError,
        OpenSSL::SSL::SSLError
      )
    end

    it 'defines NON_RETRYABLE_EXCEPTIONS' do
      expect(RetryHandler::NON_RETRYABLE_EXCEPTIONS).to include(NoMemoryError)
    end
  end
end

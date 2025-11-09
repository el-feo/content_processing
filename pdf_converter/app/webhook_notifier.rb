# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

# WebhookNotifier handles sending webhook notifications to client-provided URLs.
# It sends completion status, image URLs, page count, and processing time.
class WebhookNotifier
  # Default timeout for webhook HTTP requests (in seconds)
  DEFAULT_TIMEOUT = 10

  # Sends a webhook notification to the specified URL.
  #
  # @param webhook_url [String] The URL to send the notification to
  # @param unique_id [String] The unique identifier for this conversion request
  # @param status [String] The completion status (e.g., 'completed')
  # @param images [Array<String>] Array of uploaded image URLs
  # @param page_count [Integer] Number of pages converted
  # @param processing_time_ms [Integer] Time taken to process the PDF in milliseconds
  # @return [Hash] Result hash with :success or :error key
  def notify(webhook_url:, unique_id:, status:, images:, page_count:, processing_time_ms:)
    uri = URI.parse(webhook_url)

    payload = build_payload(
      unique_id: unique_id,
      status: status,
      images: images,
      page_count: page_count,
      processing_time_ms: processing_time_ms
    )

    response = send_request(uri, payload)

    if response.is_a?(Net::HTTPSuccess)
      puts "Webhook notification sent successfully to #{webhook_url}"
      { success: true }
    else
      error_msg = "Webhook returned HTTP #{response.code}: #{response.body}"
      { error: error_msg }
    end
  rescue StandardError => e
    { error: "Webhook error: #{e.message}" }
  end

  private

  # Builds the JSON payload for the webhook notification.
  #
  # @param unique_id [String] The unique identifier for this conversion request
  # @param status [String] The completion status
  # @param images [Array<String>] Array of uploaded image URLs
  # @param page_count [Integer] Number of pages converted
  # @param processing_time_ms [Integer] Processing time in milliseconds
  # @return [Hash] The payload hash
  def build_payload(unique_id:, status:, images:, page_count:, processing_time_ms:)
    {
      unique_id: unique_id,
      status: status,
      images: images,
      page_count: page_count,
      processing_time_ms: processing_time_ms
    }
  end

  # Sends the HTTP POST request to the webhook URL.
  #
  # @param uri [URI] The parsed webhook URI
  # @param payload [Hash] The payload to send
  # @return [Net::HTTPResponse] The HTTP response
  def send_request(uri, payload)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.read_timeout = DEFAULT_TIMEOUT
      http.open_timeout = DEFAULT_TIMEOUT
      http.request(request)
    end
  end
end

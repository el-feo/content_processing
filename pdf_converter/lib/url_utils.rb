# frozen_string_literal: true

require 'uri'

# UrlUtils provides utility methods for URL operations.
# This module contains shared functionality used across multiple classes.
module UrlUtils
  # Sanitizes URL for logging by removing query parameters that might contain secrets.
  #
  # @param url [String] The URL to sanitize
  # @return [String] Sanitized URL with query parameters hidden
  def sanitize_url(url)
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}#{uri.path}[QUERY_PARAMS_HIDDEN]"
  rescue StandardError
    '[URL_PARSE_ERROR]'
  end

  # Removes query parameters from URLs.
  #
  # @param urls [Array<String>] URLs with query parameters
  # @return [Array<String>] URLs without query parameters
  def self.strip_query_params(urls)
    urls.map { |url| url.split('?').first }
  end
end

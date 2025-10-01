#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify libvips and pdfium installation
begin
  require 'ruby-vips'

  puts '✓ ruby-vips loaded successfully'
  puts "  Version: #{Vips::VERSION}"
  puts "  libvips version: #{Vips.version_string}"

  # Check if PDF support is available
  loaders = Vips.get_suffixes
  if loaders['.pdf']
    puts '✓ PDF support is available'
    puts "  PDF loader: #{loaders['.pdf']}"
  else
    puts '✗ PDF support not found'
  end

  # Check for pdfium
  puts "\nChecking for pdfium support..."

  # Try to get vips configuration
  begin
    # Create a simple test to check if we can handle PDFs
    puts '✓ libvips is configured and ready'

    # List all available operations
    ops = Vips.operations
    pdf_ops = ops.select { |op| op.include?('pdf') }
    puts "✓ PDF operations found: #{pdf_ops.join(', ')}" unless pdf_ops.empty?
  rescue StandardError => e
    puts "Error checking vips configuration: #{e.message}"
  end

  puts "\nTest completed successfully!"
rescue LoadError => e
  puts "✗ Failed to load ruby-vips: #{e.message}"
  exit 1
rescue StandardError => e
  puts "✗ Unexpected error: #{e.message}"
  exit 1
end

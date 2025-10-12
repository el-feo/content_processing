# frozen_string_literal: true

require 'vips'
require 'tempfile'
require 'fileutils'
require 'logger'

# PdfConverter handles conversion of PDF documents to PNG images
# using libvips with streaming support for memory efficiency
class PdfConverter
  attr_reader :dpi, :compression, :max_pages

  def initialize(logger: nil)
    @logger = logger || Logger.new($stdout)
    @dpi = (ENV['CONVERSION_DPI'] || '300').to_i
    @compression = (ENV['PNG_COMPRESSION'] || '6').to_i
    @max_pages = (ENV['MAX_PAGES'] || '500').to_i
  end

  # Convert PDF content to PNG images
  # @param pdf_content [String] The PDF file content
  # @param output_dir [String] Directory to save PNG files
  # @param unique_id [String] Unique identifier for naming files
  # @param options [Hash] Optional conversion settings
  # @return [Hash] Result with :success, :images array, :metadata, or :error
  def convert_to_images(pdf_content:, output_dir:, unique_id:, **options)
    # Override defaults with options if provided
    conversion_dpi = options[:dpi] || @dpi

    # Ensure output directory exists
    FileUtils.mkdir_p(output_dir)

    # Validate PDF content
    return error_result('Invalid PDF content') unless valid_pdf?(pdf_content)

    # Create temporary file for PDF
    temp_pdf = create_temp_pdf(pdf_content)

    begin
      # Get page count
      page_count = get_page_count_from_file(temp_pdf.path)

      return error_result('PDF has no pages') if page_count.zero?

      return error_result("PDF has #{page_count} pages, exceeding maximum of #{@max_pages}") if page_count > @max_pages

      # Convert pages to images
      images = []
      log_info("Starting conversion of #{page_count} pages at #{conversion_dpi} DPI")

      (0...page_count).each do |page_index|
        image_path = convert_page(
          temp_pdf.path,
          page_index,
          output_dir,
          unique_id,
          conversion_dpi
        )
        images << image_path
        log_info("Converted page #{page_index + 1}/#{page_count}")

        # Force garbage collection every 10 pages for memory management
        GC.start if ((page_index + 1) % 10).zero?
      end

      {
        success: true,
        images: images,
        metadata: {
          page_count: page_count,
          dpi: conversion_dpi,
          compression: @compression
        }
      }
    rescue StandardError => e
      error_result("PDF conversion failed: #{e.message}")
    ensure
      # Clean up temporary file
      temp_pdf&.close
      temp_pdf&.unlink
    end
  end

  # Get page count from PDF content
  # @param pdf_content [String] The PDF file content
  # @return [Integer] Number of pages
  def get_page_count(pdf_content)
    return 0 unless valid_pdf?(pdf_content)

    temp_pdf = create_temp_pdf(pdf_content)
    count = get_page_count_from_file(temp_pdf.path)
    temp_pdf.close
    temp_pdf.unlink
    count
  rescue StandardError => e
    log_error("Failed to get page count: #{e.message}")
    0
  end

  private

  def valid_pdf?(content)
    return false if content.nil? || content.empty?

    content.start_with?('%PDF-')
  end

  def create_temp_pdf(content)
    temp = Tempfile.new(['pdf_converter', '.pdf'], '/tmp')
    temp.binmode
    temp.write(content)
    temp.rewind
    temp
  end

  def get_page_count_from_file(pdf_path)
    # Load PDF to get page count
    # Vips.pdfload returns an image, n=-1 loads all pages
    image = Vips::Image.pdfload(pdf_path, n: -1, dpi: 1)
    # Calculate page count from image height
    # Each page is loaded vertically, so total height / page height = page count
    first_page = Vips::Image.pdfload(pdf_path, n: 1, dpi: 1)
    (image.height / first_page.height).to_i
  rescue StandardError => e
    log_error("Failed to load PDF for page count: #{e.message}")
    0
  end

  def convert_page(pdf_path, page_index, output_dir, unique_id, dpi)
    # Page number for filename (1-indexed)
    page_number = page_index + 1
    output_filename = "#{unique_id}_page_#{page_number}.png"
    output_path = File.join(output_dir, output_filename)

    # Load specific page from PDF
    image = Vips::Image.pdfload(pdf_path, page: page_index, n: 1, dpi: dpi)

    # Convert to PNG with compression
    image.pngsave(output_path, compression: @compression)

    output_path
  rescue StandardError => e
    log_error("Failed to convert page #{page_index + 1}: #{e.message}")
    raise
  end

  def error_result(message)
    log_error(message)
    {
      success: false,
      error: message
    }
  end

  def log_info(message)
    @logger.info("PdfConverter: #{message}")
  end

  def log_error(message)
    @logger.error("PdfConverter: #{message}")
  end
end

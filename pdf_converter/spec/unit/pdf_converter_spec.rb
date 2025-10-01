# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'
require_relative '../../pdf_converter'

RSpec.describe PdfConverter, skip: 'ruby-vips not available in local environment' do
  let(:converter) { PdfConverter.new }
  let(:sample_pdf_path) { File.expand_path('../fixtures/sample.pdf', __dir__) }
  let(:output_dir) { Dir.mktmpdir('pdf_converter_test') }
  let(:unique_id) { 'test-123' }

  before do
    # Create a sample PDF for testing
    FileUtils.mkdir_p(File.dirname(sample_pdf_path))
    unless File.exist?(sample_pdf_path)
      File.write(sample_pdf_path,
                 "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n>>\nendobj\nxref\n0 1\n0000000000 65535 f \ntrailer\n<<\n/Size 1\n/Root 1 0 R\n>>\nstartxref\n9\n%%EOF")
    end
  end

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe '#initialize' do
    it 'creates a new PdfConverter instance' do
      expect(converter).to be_a(PdfConverter)
    end

    it 'sets default DPI from environment variable' do
      ENV['CONVERSION_DPI'] = '150'
      converter = PdfConverter.new
      expect(converter.dpi).to eq(150)
      ENV.delete('CONVERSION_DPI')
    end

    it 'uses default DPI of 300 when environment variable is not set' do
      ENV.delete('CONVERSION_DPI')
      converter = PdfConverter.new
      expect(converter.dpi).to eq(300)
    end
  end

  describe '#convert_to_images' do
    it 'converts PDF to PNG images' do
      result = converter.convert_to_images(
        pdf_content: File.read(sample_pdf_path),
        output_dir: output_dir,
        unique_id: unique_id
      )

      expect(result[:success]).to be true
      expect(result[:images]).to be_an(Array)
      expect(result[:images]).not_to be_empty
    end

    it 'creates PNG files with correct naming convention' do
      converter.convert_to_images(
        pdf_content: File.read(sample_pdf_path),
        output_dir: output_dir,
        unique_id: unique_id
      )

      expected_file = File.join(output_dir, "#{unique_id}_page_1.png")
      expect(File.exist?(expected_file)).to be true
    end

    it 'returns error for invalid PDF content' do
      result = converter.convert_to_images(
        pdf_content: 'not a pdf',
        output_dir: output_dir,
        unique_id: unique_id
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include('Invalid PDF')
    end

    it 'handles missing output directory' do
      non_existent_dir = '/tmp/non_existent_dir_12345'
      FileUtils.rm_rf(non_existent_dir)

      result = converter.convert_to_images(
        pdf_content: File.read(sample_pdf_path),
        output_dir: non_existent_dir,
        unique_id: unique_id
      )

      # Should create the directory
      expect(result[:success]).to be true
      expect(Dir.exist?(non_existent_dir)).to be true
      FileUtils.rm_rf(non_existent_dir)
    end
  end

  describe '#convert_with_options' do
    it 'accepts custom DPI setting' do
      result = converter.convert_to_images(
        pdf_content: File.read(sample_pdf_path),
        output_dir: output_dir,
        unique_id: unique_id,
        dpi: 150
      )

      expect(result[:success]).to be true
      expect(result[:metadata][:dpi]).to eq(150)
    end

    it 'applies PNG compression settings' do
      ENV['PNG_COMPRESSION'] = '9'
      converter = PdfConverter.new

      result = converter.convert_to_images(
        pdf_content: File.read(sample_pdf_path),
        output_dir: output_dir,
        unique_id: unique_id
      )

      expect(result[:success]).to be true
      ENV.delete('PNG_COMPRESSION')
    end
  end

  describe '#page_count' do
    it 'returns correct page count for PDF' do
      count = converter.get_page_count(File.read(sample_pdf_path))
      expect(count).to be >= 1
    end

    it 'returns 0 for invalid PDF' do
      count = converter.get_page_count('not a pdf')
      expect(count).to eq(0)
    end
  end

  describe '#cleanup' do
    it 'cleans up temporary files after conversion' do
      converter.convert_to_images(
        pdf_content: File.read(sample_pdf_path),
        output_dir: output_dir,
        unique_id: unique_id
      )

      # Check that /tmp doesn't have leftover PDF files
      temp_pdfs = Dir.glob('/tmp/*.pdf').select { |f| f.include?('vips') }
      expect(temp_pdfs).to be_empty
    end
  end
end

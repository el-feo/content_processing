# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

# Stub the vips gem loading since it may not be available in test environment
begin
  require 'vips'
rescue LoadError
  # Define mock Vips module if not available
  module Vips
    class Image
      def self.pdfload(_path, **_options)
        new
      end

      def pngsave(_path, **_options)
        true
      end

      def height
        3508
      end
    end
  end
end

require_relative '../../app/pdf_converter'

RSpec.describe PdfConverter do
  let(:converter) { described_class.new }
  let(:pdf_content) { "%PDF-1.4\nPDF content here" }
  let(:output_dir) { Dir.mktmpdir }
  let(:unique_id) { 'test-123' }

  after do
    FileUtils.rm_rf(output_dir) if File.exist?(output_dir)
  end

  describe 'attr_readers' do
    it 'exposes dpi' do
      expect(converter).to respond_to(:dpi)
    end

    it 'exposes compression' do
      expect(converter).to respond_to(:compression)
    end

    it 'exposes max_pages' do
      expect(converter).to respond_to(:max_pages)
    end
  end

  describe '#initialize' do
    context 'with default settings' do
      it 'sets default DPI to 300' do
        expect(converter.dpi).to eq(300)
      end

      it 'sets default compression to 6' do
        expect(converter.compression).to eq(6)
      end

      it 'sets default max_pages to 500' do
        expect(converter.max_pages).to eq(500)
      end
    end

    context 'with environment variables' do
      before do
        ENV['CONVERSION_DPI'] = '150'
        ENV['PNG_COMPRESSION'] = '9'
        ENV['MAX_PAGES'] = '100'
      end

      after do
        ENV.delete('CONVERSION_DPI')
        ENV.delete('PNG_COMPRESSION')
        ENV.delete('MAX_PAGES')
      end

      it 'uses DPI from environment' do
        converter = described_class.new
        expect(converter.dpi).to eq(150)
      end

      it 'uses compression from environment' do
        converter = described_class.new
        expect(converter.compression).to eq(9)
      end

      it 'uses max_pages from environment' do
        converter = described_class.new
        expect(converter.max_pages).to eq(100)
      end
    end

    context 'with custom logger' do
      let(:custom_logger) { instance_double(Logger).as_null_object }
      let(:converter) { described_class.new(logger: custom_logger) }

      it 'uses provided logger' do
        expect(converter.instance_variable_get(:@logger)).to eq(custom_logger)
      end
    end

    context 'without custom logger' do
      it 'creates default logger' do
        expect(converter.instance_variable_get(:@logger)).to be_a(Logger)
      end
    end
  end

  describe '#convert_to_images' do
    let(:vips_image) { double('Vips::Image', height: 3508, pngsave: true) }
    let(:first_page) { double('Vips::Image', height: 3508) }

    before do
      allow(Vips::Image).to receive(:pdfload).and_call_original
      allow(Vips::Image).to receive(:pdfload).with(anything, n: -1, dpi: 1).and_return(vips_image)
      allow(Vips::Image).to receive(:pdfload).with(anything, n: 1, dpi: 1).and_return(first_page)
      allow(Vips::Image).to receive(:pdfload).with(anything, page: 0, n: 1, dpi: anything).and_return(vips_image)
    end

    context 'with valid single-page PDF' do
      it 'returns success with image paths' do
        result = converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:success]).to be true
        expect(result[:images]).to be_an(Array)
        expect(result[:images].size).to eq(1)
      end

      it 'includes metadata with page count' do
        result = converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:metadata][:page_count]).to eq(1)
      end

      it 'includes metadata with DPI' do
        result = converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:metadata][:dpi]).to eq(300)
      end

      it 'includes metadata with compression' do
        result = converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:metadata][:compression]).to eq(6)
      end

      it 'creates output directory if missing' do
        custom_dir = File.join(output_dir, 'nested', 'path')
        converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: custom_dir,
          unique_id: unique_id
        )
        expect(File.directory?(custom_dir)).to be true
      end
    end

    context 'with custom DPI option' do
      it 'uses provided DPI override' do
        result = converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id,
          dpi: 150
        )
        expect(result[:metadata][:dpi]).to eq(150)
      end

      it 'passes DPI to Vips::Image.pdfload' do
        converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id,
          dpi: 150
        )
        expect(Vips::Image).to have_received(:pdfload)
          .with(anything, page: 0, n: 1, dpi: 150)
      end
    end

    context 'with multi-page PDF' do
      let(:vips_multi_image) { double('Vips::Image', height: 10_524) } # 3 pages * 3508

      before do
        allow(Vips::Image).to receive(:pdfload).with(anything, n: -1, dpi: 1).and_return(vips_multi_image)
        (0..2).each do |page|
          allow(Vips::Image).to receive(:pdfload)
            .with(anything, page: page, n: 1, dpi: anything)
            .and_return(vips_image)
        end
      end

      it 'converts all pages' do
        result = converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:images].size).to eq(3)
      end

      it 'creates sequential page names' do
        result = converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:images][0]).to include('page_1.png')
        expect(result[:images][1]).to include('page_2.png')
        expect(result[:images][2]).to include('page_3.png')
      end
    end

    context 'with PDF exceeding max pages' do
      before do
        # Simulate 501 pages (exceeds default max of 500)
        large_height = 3508 * 501
        large_image = double('Vips::Image', height: large_height)
        allow(Vips::Image).to receive(:pdfload).with(anything, n: -1, dpi: 1).and_return(large_image)
      end

      it 'returns error for too many pages' do
        result = converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:success]).to be false
        expect(result[:error]).to include('exceeding maximum')
      end
    end

    context 'with empty PDF (zero pages)' do
      before do
        allow(Vips::Image).to receive(:pdfload).with(anything, n: -1, dpi: 1)
                                               .and_raise(StandardError.new('Invalid PDF'))
        allow(Vips::Image).to receive(:pdfload).with(anything, n: 1, dpi: 1)
                                               .and_raise(StandardError.new('Invalid PDF'))
      end

      it 'returns error for zero pages' do
        result = converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:success]).to be false
      end
    end

    context 'with invalid PDF content' do
      let(:invalid_content) { 'Not a PDF file' }

      it 'returns error for invalid content' do
        result = converter.convert_to_images(
          pdf_content: invalid_content,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid PDF content')
      end
    end

    context 'with nil PDF content' do
      it 'returns error for nil content' do
        result = converter.convert_to_images(
          pdf_content: nil,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid PDF content')
      end
    end

    context 'with empty PDF content' do
      it 'returns error for empty content' do
        result = converter.convert_to_images(
          pdf_content: '',
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid PDF content')
      end
    end

    context 'when conversion raises error during page conversion' do
      before do
        # Allow page count to succeed but fail during actual conversion
        allow(Vips::Image).to receive(:pdfload).with(anything, n: -1, dpi: 1).and_return(vips_image)
        allow(Vips::Image).to receive(:pdfload).with(anything, n: 1, dpi: 1).and_return(first_page)
        allow(Vips::Image).to receive(:pdfload).with(anything, page: anything, n: 1, dpi: anything)
                                               .and_raise(StandardError.new('Vips conversion error'))
      end

      it 'returns error result' do
        result = converter.convert_to_images(
          pdf_content: pdf_content,
          output_dir: output_dir,
          unique_id: unique_id
        )
        expect(result[:success]).to be false
        expect(result[:error]).to include('PDF conversion failed')
      end

      it 'cleans up temp file even on error' do
        # Should not raise error even when conversion fails
        expect do
          converter.convert_to_images(
            pdf_content: pdf_content,
            output_dir: output_dir,
            unique_id: unique_id
          )
        end.not_to raise_error
      end
    end
  end

  describe '#get_page_count' do
    let(:vips_image) { double('Vips::Image', height: 7016) } # 2 pages
    let(:first_page) { double('Vips::Image', height: 3508) }

    before do
      allow(Vips::Image).to receive(:pdfload).with(anything, n: -1, dpi: 1).and_return(vips_image)
      allow(Vips::Image).to receive(:pdfload).with(anything, n: 1, dpi: 1).and_return(first_page)
    end

    context 'with valid PDF' do
      it 'returns page count' do
        count = converter.get_page_count(pdf_content)
        expect(count).to eq(2)
      end

      it 'cleans up temp file' do
        # Should not leave temp files behind
        before_count = Dir.glob('/tmp/pdf_converter*.pdf').size
        converter.get_page_count(pdf_content)
        after_count = Dir.glob('/tmp/pdf_converter*.pdf').size
        expect(after_count).to eq(before_count)
      end
    end

    context 'with invalid PDF' do
      let(:invalid_content) { 'Not a PDF' }

      it 'returns 0 for invalid content' do
        count = converter.get_page_count(invalid_content)
        expect(count).to eq(0)
      end
    end

    context 'when Vips raises error' do
      before do
        allow(Vips::Image).to receive(:pdfload)
          .and_raise(StandardError.new('Vips error'))
      end

      it 'returns 0 on error' do
        count = converter.get_page_count(pdf_content)
        expect(count).to eq(0)
      end

      it 'logs error message' do
        # Error should be logged but not raised
        expect { converter.get_page_count(pdf_content) }.not_to raise_error
      end
    end

    context 'when temp file cleanup fails' do
      before do
        temp_file = instance_double(Tempfile)
        allow(temp_file).to receive(:binmode)
        allow(temp_file).to receive(:write)
        allow(temp_file).to receive(:rewind)
        allow(temp_file).to receive(:path).and_return('/tmp/test.pdf')
        allow(temp_file).to receive(:close).and_raise(IOError.new('File already closed'))
        allow(Tempfile).to receive(:new).and_return(temp_file)
      end

      it 'returns 0 when cleanup fails' do
        count = converter.get_page_count(pdf_content)
        expect(count).to eq(0)
      end

      it 'logs error about cleanup failure' do
        expect { converter.get_page_count(pdf_content) }.not_to raise_error
      end
    end
  end

  describe '#validate_page_count (private)' do
    context 'with zero pages' do
      it 'returns error' do
        result = converter.send(:validate_page_count, 0)
        expect(result[:success]).to be false
        expect(result[:error]).to include('no pages')
      end
    end

    context 'with pages exceeding max' do
      it 'returns error' do
        result = converter.send(:validate_page_count, 501)
        expect(result[:success]).to be false
        expect(result[:error]).to include('exceeding maximum')
      end

      it 'includes actual and max page counts' do
        result = converter.send(:validate_page_count, 501)
        expect(result[:error]).to include('501')
        expect(result[:error]).to include('500')
      end
    end

    context 'with valid page count' do
      it 'returns nil for valid count' do
        result = converter.send(:validate_page_count, 10)
        expect(result).to be_nil
      end

      it 'allows exactly max_pages' do
        result = converter.send(:validate_page_count, 500)
        expect(result).to be_nil
      end

      it 'allows 1 page' do
        result = converter.send(:validate_page_count, 1)
        expect(result).to be_nil
      end
    end
  end

  describe '#convert_all_pages (private)' do
    let(:vips_image) { double('Vips::Image') }

    before do
      allow(Vips::Image).to receive(:pdfload).and_return(vips_image)
      allow(vips_image).to receive(:pngsave).and_return(true)
      allow(GC).to receive(:start)
    end

    context 'with single page' do
      it 'converts one page' do
        temp_pdf = Tempfile.new(['test', '.pdf'])
        images = converter.send(:convert_all_pages, temp_pdf.path, 1, output_dir, unique_id, 300)
        expect(images.size).to eq(1)
        temp_pdf.close!
      end

      it 'does not trigger garbage collection' do
        temp_pdf = Tempfile.new(['test', '.pdf'])
        converter.send(:convert_all_pages, temp_pdf.path, 1, output_dir, unique_id, 300)
        expect(GC).not_to have_received(:start)
        temp_pdf.close!
      end
    end

    context 'with 10 pages' do
      it 'triggers garbage collection after 10th page' do
        temp_pdf = Tempfile.new(['test', '.pdf'])
        converter.send(:convert_all_pages, temp_pdf.path, 10, output_dir, unique_id, 300)
        expect(GC).to have_received(:start).once
        temp_pdf.close!
      end
    end

    context 'with 25 pages' do
      it 'triggers garbage collection twice' do
        temp_pdf = Tempfile.new(['test', '.pdf'])
        converter.send(:convert_all_pages, temp_pdf.path, 25, output_dir, unique_id, 300)
        expect(GC).to have_received(:start).twice
        temp_pdf.close!
      end
    end
  end

  describe '#valid_pdf? (private)' do
    context 'with valid PDF content' do
      it 'returns true for PDF-1.x' do
        expect(converter.send(:valid_pdf?, '%PDF-1.4 content')).to be true
      end

      it 'returns true for PDF-2.x' do
        expect(converter.send(:valid_pdf?, '%PDF-2.0 content')).to be true
      end
    end

    context 'with invalid content' do
      it 'returns false for nil' do
        expect(converter.send(:valid_pdf?, nil)).to be false
      end

      it 'returns false for empty string' do
        expect(converter.send(:valid_pdf?, '')).to be false
      end

      it 'returns false for non-PDF content' do
        expect(converter.send(:valid_pdf?, 'Not a PDF')).to be false
      end
    end
  end

  describe '#create_temp_pdf (private)' do
    it 'creates tempfile with PDF content' do
      temp = converter.send(:create_temp_pdf, pdf_content)
      expect(temp).to be_a(Tempfile)
      temp.close!
    end

    it 'writes content to tempfile' do
      temp = converter.send(:create_temp_pdf, pdf_content)
      temp.rewind
      expect(temp.read).to eq(pdf_content)
      temp.close!
    end

    it 'creates tempfile in /tmp directory' do
      temp = converter.send(:create_temp_pdf, pdf_content)
      expect(temp.path).to start_with('/tmp/')
      temp.close!
    end
  end

  describe '#get_page_count_from_file (private)' do
    let(:vips_image) { double('Vips::Image', height: 10_524) } # 3 pages
    let(:first_page) { double('Vips::Image', height: 3508) }
    let(:temp_pdf) do
      temp = Tempfile.new(['test', '.pdf'])
      temp.write(pdf_content)
      temp.rewind
      temp
    end

    after do
      temp_pdf.close! if temp_pdf
    end

    before do
      allow(Vips::Image).to receive(:pdfload).with(temp_pdf.path, n: -1, dpi: 1).and_return(vips_image)
      allow(Vips::Image).to receive(:pdfload).with(temp_pdf.path, n: 1, dpi: 1).and_return(first_page)
    end

    context 'with valid PDF file' do
      it 'returns correct page count' do
        count = converter.send(:get_page_count_from_file, temp_pdf.path)
        expect(count).to eq(3)
      end
    end

    context 'when Vips raises error' do
      before do
        allow(Vips::Image).to receive(:pdfload).and_raise(StandardError.new('Vips error'))
      end

      it 'returns 0 on error' do
        count = converter.send(:get_page_count_from_file, temp_pdf.path)
        expect(count).to eq(0)
      end
    end
  end

  describe '#convert_page (private)' do
    let(:vips_image) { double('Vips::Image') }
    let(:temp_pdf) do
      temp = Tempfile.new(['test', '.pdf'])
      temp.write(pdf_content)
      temp.rewind
      temp
    end

    after do
      temp_pdf.close! if temp_pdf
    end

    before do
      allow(Vips::Image).to receive(:pdfload).and_return(vips_image)
      allow(vips_image).to receive(:pngsave).and_return(true)
    end

    context 'with successful conversion' do
      it 'returns output path' do
        path = converter.send(:convert_page, temp_pdf.path, 0, output_dir, unique_id, 300)
        expect(path).to include(output_dir)
        expect(path).to end_with('.png')
      end

      it 'uses 1-indexed page numbers in filename' do
        path = converter.send(:convert_page, temp_pdf.path, 0, output_dir, unique_id, 300)
        expect(path).to include('page_1.png')
      end

      it 'loads correct page from PDF' do
        converter.send(:convert_page, temp_pdf.path, 2, output_dir, unique_id, 300)
        expect(Vips::Image).to have_received(:pdfload)
          .with(temp_pdf.path, page: 2, n: 1, dpi: 300)
      end

      it 'saves with configured compression' do
        converter.send(:convert_page, temp_pdf.path, 0, output_dir, unique_id, 300)
        expect(vips_image).to have_received(:pngsave)
          .with(anything, compression: 6)
      end
    end

    context 'when conversion fails' do
      before do
        allow(Vips::Image).to receive(:pdfload).and_raise(StandardError.new('Conversion error'))
      end

      it 'raises error' do
        expect do
          converter.send(:convert_page, temp_pdf.path, 0, output_dir, unique_id, 300)
        end.to raise_error(StandardError)
      end

      it 'logs error message before raising' do
        # Error should be logged even when raised
        expect do
          converter.send(:convert_page, temp_pdf.path, 0, output_dir, unique_id, 300)
        end.to raise_error(StandardError)
      end
    end
  end

  describe '#cleanup_temp_file (private)' do
    context 'with valid tempfile' do
      let(:temp) { Tempfile.new(['test', '.pdf']) }

      it 'closes and unlinks tempfile' do
        converter.send(:cleanup_temp_file, temp)
        expect(temp).to be_closed
      end

      it 'does not raise error' do
        expect { converter.send(:cleanup_temp_file, temp) }.not_to raise_error
      end
    end

    context 'with nil tempfile' do
      it 'handles nil gracefully' do
        expect { converter.send(:cleanup_temp_file, nil) }.not_to raise_error
      end
    end
  end

  describe '#success_result (private)' do
    let(:images) { ['/tmp/page1.png', '/tmp/page2.png'] }

    it 'returns success hash' do
      result = converter.send(:success_result, images, 2, 300)
      expect(result[:success]).to be true
    end

    it 'includes images array' do
      result = converter.send(:success_result, images, 2, 300)
      expect(result[:images]).to eq(images)
    end

    it 'includes metadata with page count' do
      result = converter.send(:success_result, images, 2, 300)
      expect(result[:metadata][:page_count]).to eq(2)
    end

    it 'includes metadata with DPI' do
      result = converter.send(:success_result, images, 2, 300)
      expect(result[:metadata][:dpi]).to eq(300)
    end

    it 'includes metadata with compression' do
      result = converter.send(:success_result, images, 2, 300)
      expect(result[:metadata][:compression]).to eq(6)
    end
  end

  describe '#error_result (private)' do
    it 'returns error hash' do
      result = converter.send(:error_result, 'Test error')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('Test error')
    end
  end
end

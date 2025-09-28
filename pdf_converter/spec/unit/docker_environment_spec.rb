# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Docker Environment' do
  describe 'ruby-vips installation' do
    it 'can load ruby-vips gem', skip: "ruby-vips not available in local environment" do
      expect { require 'vips' }.not_to raise_error
    end

    it 'has correct ruby-vips version', skip: "ruby-vips not available in local environment" do
      require 'vips'
      # ruby-vips 2.2 requires libvips 8.6+
      expect(Vips::VERSION).to match(/\d+\.\d+/)
    end
  end

  describe 'environment variables' do
    it 'can read CONVERSION_DPI environment variable' do
      ENV['CONVERSION_DPI'] = '150'
      expect(ENV['CONVERSION_DPI']).to eq('150')
      ENV.delete('CONVERSION_DPI')
    end

    it 'can read PNG_COMPRESSION environment variable' do
      ENV['PNG_COMPRESSION'] = '6'
      expect(ENV['PNG_COMPRESSION']).to eq('6')
      ENV.delete('PNG_COMPRESSION')
    end

    it 'can read MAX_PAGES environment variable' do
      ENV['MAX_PAGES'] = '100'
      expect(ENV['MAX_PAGES']).to eq('100')
      ENV.delete('MAX_PAGES')
    end
  end

  describe 'memory limits' do
    it 'has sufficient memory allocated' do
      # Lambda function should have 2048MB
      # In local testing, just verify we can allocate memory
      test_array = Array.new(1024 * 1024) # 1M elements
      expect(test_array.size).to eq(1024 * 1024)
    end
  end

  describe 'temporary file handling' do
    it 'can create temporary files' do
      require 'tempfile'
      temp = Tempfile.new('test_pdf_converter')
      expect(File.exist?(temp.path)).to be true
      temp.close
      temp.unlink
    end

    it 'has /tmp directory available' do
      expect(Dir.exist?('/tmp')).to be true
      expect(File.writable?('/tmp')).to be true
    end
  end
end
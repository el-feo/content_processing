# frozen_string_literal: true

require 'spec_helper'
require 'zip'
require 'tempfile'
require_relative '../../lib/zip_builder'

RSpec.describe ZipBuilder do
  describe '.create_from_images' do
    let(:unique_id) { 'test-123' }
    let(:temp_files) do
      [
        Tempfile.new(['test-1', '.png']),
        Tempfile.new(['test-2', '.png'])
      ]
    end
    let(:image_paths) { temp_files.map(&:path) }

    before do
      temp_files.each_with_index do |file, index|
        file.write("content-#{index + 1}")
        file.rewind
      end
    end

    after do
      temp_files.each(&:close!)
    end

    it 'creates a zip file with images' do
      zip_content = described_class.create_from_images(image_paths, unique_id)
      expect(zip_content).to be_a(String)
      expect(zip_content).not_to be_empty
    end

    it 'names images with unique_id prefix' do
      zip_content = described_class.create_from_images(image_paths, unique_id)

      # Read the zip to verify entry names
      zip_stream = StringIO.new(zip_content)
      Zip::File.open_buffer(zip_stream) do |zip_file|
        entries = zip_file.entries.map(&:name)
        expect(entries).to include('test-123-0.png')
        expect(entries).to include('test-123-1.png')
      end
    end

    it 'includes image contents in zip' do
      zip_content = described_class.create_from_images(image_paths, unique_id)

      # Read the zip to verify contents
      zip_stream = StringIO.new(zip_content)
      Zip::File.open_buffer(zip_stream) do |zip_file|
        expect(zip_file.read('test-123-0.png')).to eq('content-1')
        expect(zip_file.read('test-123-1.png')).to eq('content-2')
      end
    end

    it 'handles empty image paths array' do
      zip_content = described_class.create_from_images([], unique_id)

      zip_stream = StringIO.new(zip_content)
      Zip::File.open_buffer(zip_stream) do |zip_file|
        expect(zip_file.entries).to be_empty
      end
    end

    it 'correctly orders images by index' do
      zip_content = described_class.create_from_images(image_paths, unique_id)

      zip_stream = StringIO.new(zip_content)
      Zip::File.open_buffer(zip_stream) do |zip_file|
        entry_names = zip_file.entries.map(&:name)
        expect(entry_names[0]).to eq('test-123-0.png')
        expect(entry_names[1]).to eq('test-123-1.png')
      end
    end
  end
end

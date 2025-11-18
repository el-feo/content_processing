# frozen_string_literal: true

require 'zip'

# ZipBuilder creates zip files in memory from image files
# Extracted to reduce complexity and improve separation of concerns
class ZipBuilder
  # Creates a zip file in memory from image files
  # @param image_paths [Array<String>] Array of image file paths
  # @param unique_id [String] Unique identifier for naming images
  # @return [String] Binary content of the zip file
  def self.create_from_images(image_paths, unique_id)
    zip_stream = Zip::OutputStream.write_buffer do |zip|
      add_images_to_zip(zip, image_paths, unique_id)
    end

    zip_stream.rewind
    zip_stream.read
  end

  # Adds images to a zip stream
  # @param zip [Zip::OutputStream] The zip stream to write to
  # @param image_paths [Array<String>] Array of image file paths
  # @param unique_id [String] Unique identifier for naming images
  def self.add_images_to_zip(zip, image_paths, unique_id)
    image_paths.each_with_index do |image_path, index|
      entry_name = build_entry_name(unique_id, index)
      zip.put_next_entry(entry_name)
      zip.write(File.read(image_path, mode: 'rb'))
    end
  end

  # Builds the entry name for an image in the zip
  # @param unique_id [String] Unique identifier
  # @param index [Integer] Image index
  # @return [String] Entry name (e.g., "unique_id-0.png")
  def self.build_entry_name(unique_id, index)
    "#{unique_id}-#{index}.png"
  end

  private_class_method :add_images_to_zip, :build_entry_name
end

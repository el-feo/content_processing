<objective>
Modify the PDF converter to zip all generated images and stream the zip file directly to the destination S3 URL instead of uploading individual images. Update all documentation to reflect that the destination pre-signed URL should be for a zip file (e.g., output.zip).

This change simplifies client integration by providing a single zip file containing all converted pages, reducing API response complexity and improving download efficiency.
</objective>

<context>
This is a serverless PDF to image conversion service built with AWS SAM and Ruby Lambda functions. The service currently:
- Accepts pre-signed S3 URLs for source (PDF) and destination (folder for images)
- Converts PDF pages to PNG images
- Uploads each image individually to S3

We need to change the upload behavior to create a zip file containing all images and stream it to the destination URL.

Review the current implementation:
- @pdf_converter/app.rb - Main Lambda handler and conversion logic
- @pdf_converter/lib/image_uploader.rb - Current image upload implementation
- @CLAUDE.md - Project conventions and setup
- @README.md - User-facing documentation
</context>

<requirements>
1. **Code Changes:**
   - Modify the image upload process to create a zip file containing all converted PNG images
   - Stream the zip file directly to the destination S3 URL (no temporary local file storage if possible, or clean up if needed)
   - Maintain the naming convention for images inside the zip: `{unique_id}-0.png`, `{unique_id}-1.png`, etc.
   - Update the response format to reflect the new behavior (single zip URL instead of array of image URLs)
   - Ensure proper error handling for zip creation and upload

2. **Response Format Changes:**
   - Change `images` field from an array of URLs to a single string containing the destination zip URL
   - Update the response message to reflect zip delivery
   - Keep all other response fields (unique_id, status, pages_converted, metadata)

3. **Documentation Updates:**
   - Update CLAUDE.md API specification to show destination should be a zip file URL
   - Update README.md examples to show pre-signed URLs for zip files
   - Update any inline code comments to reflect the new behavior
   - Ensure all documentation consistently refers to "zip file" as the output format

4. **Dependencies:**
   - Add the 'rubyzip' gem to handle zip file creation
   - Update Gemfile and ensure bundle install is reflected in Dockerfile if needed
</requirements>

<implementation>
Approach:
1. Add rubyzip gem dependency
2. Modify ImageUploader or create a ZipUploader class to:
   - Accept an array of image file paths and the destination URL
   - Create a zip file in memory or in /tmp
   - Stream/upload the zip to the pre-signed S3 URL via HTTP PUT
   - Clean up temporary files
3. Update app.rb to use the new zip upload functionality
4. Modify the response JSON structure
5. Update all documentation files

Constraints:
- Maintain the synchronous processing model - the response should include the zip URL immediately
- Do NOT change the authentication mechanism (JWT) or request validation
- Preserve the webhook notification functionality
- Maintain backwards compatibility with existing error handling patterns
- Use streaming or temporary file cleanup to avoid Lambda /tmp storage limits (512MB max)
</implementation>

<output>
Modify/create these files:
- `pdf_converter/Gemfile` - Add rubyzip gem
- `pdf_converter/lib/image_uploader.rb` - Modify to create and upload zip, or create new ZipUploader class
- `pdf_converter/app.rb` - Update to use zip upload and modify response format
- `CLAUDE.md` - Update API specification examples
- `README.md` - Update usage examples and pre-signed URL generation instructions
- Any other files that reference the output format

Add/update tests:
- `pdf_converter/spec/unit/image_uploader_spec.rb` - Test zip creation and upload
- `pdf_converter/spec/integration/*` - Update integration tests for new response format
</output>

<verification>
Before declaring complete, verify:
1. Run the test suite: `cd pdf_converter && AWS_REGION=us-east-1 bundle exec rspec`
2. Check that all tests pass with the new zip functionality
3. Verify the response JSON structure matches the updated documentation
4. Confirm CLAUDE.md and README.md consistently refer to zip file destinations
5. Ensure Gemfile includes rubyzip and it's properly integrated
6. Check that temporary files are cleaned up after processing
</verification>

<success_criteria>
- Code successfully creates a zip file containing all converted PNG images
- Zip file is streamed/uploaded to the destination pre-signed S3 URL
- Response returns a single zip URL instead of an array of image URLs
- All tests pass
- Documentation consistently reflects the new zip-based output format
- No regression in error handling, authentication, or webhook functionality
</success_criteria>

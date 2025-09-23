# Product Roadmap

## Phase 1: Core MVP

**Goal:** Deliver basic PDF to image extraction with authentication
**Success Criteria:** Successfully process 95% of standard PDFs with JWT authentication

### Features

- [ ] JWT authentication and request validation - Implement token verification middleware `S`
- [ ] S3 signed URL validation and download - Validate and fetch PDFs from source URL `S`
- [ ] PDF to image extraction using libvips - Extract all pages as individual images `M`
- [ ] Stream upload to S3 destination - Upload extracted images without local storage `S`
- [ ] Basic webhook notification - Send success/failure status to webhook URL `S`
- [ ] Error handling and logging - Comprehensive error catching and CloudWatch logging `S`
- [ ] Unit tests with RSpec - 80% code coverage for core functionality `M`

### Dependencies

- Docker image with libvips and pdfium installed
- AWS SAM configuration and deployment
- S3 buckets for testing

## Phase 2: Performance & Reliability

**Goal:** Optimize for scale and add resilience features
**Success Criteria:** Handle 100+ concurrent requests with 99.9% success rate

### Features

- [ ] Async/concurrent page processing - Process multiple pages simultaneously `M`
- [ ] Configurable image quality/DPI - Allow quality settings in request payload `S`
- [ ] Retry logic for S3 operations - Implement exponential backoff for S3 failures `S`
- [ ] Request rate limiting - Protect against abuse with API Gateway throttling `S`
- [ ] Batch processing support - Handle multiple PDFs in single request `L`
- [ ] Progress webhooks - Send periodic progress updates for large PDFs `M`
- [ ] CloudWatch metrics and dashboards - Monitor performance and usage patterns `S`

### Dependencies

- Load testing infrastructure
- Enhanced monitoring setup
- Rate limiting configuration in API Gateway

## Phase 3: Advanced Features

**Goal:** Add value-added features for enterprise users
**Success Criteria:** Support 3+ new processing capabilities with maintained performance

### Features

- [ ] Text extraction with OCR - Extract searchable text from PDF pages `L`
- [ ] Custom watermarking - Add logos/text watermarks to extracted images `M`
- [ ] Multiple output formats - Support PNG, JPEG, WebP with compression options `M`
- [ ] Page range selection - Extract specific page ranges instead of full PDF `S`
- [ ] Metadata preservation - Maintain PDF metadata in output `S`
- [ ] Thumbnail generation - Create low-res previews alongside full images `S`

### Dependencies

- OCR engine integration (Tesseract)
- Watermarking library
- Format conversion capabilities in libvips
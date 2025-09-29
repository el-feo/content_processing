# Product Roadmap

## Phase 1: Core MVP

**Goal:** Deliver basic PDF to image conversion with authentication
**Success Criteria:** Successfully convert single PDFs to images with JWT authentication

### Features

- [x] JWT authentication with AWS Secrets Manager - Validate Bearer tokens against shared secret `S`
- [x] Request validation - Verify required fields and format `S`
- [x] PDF download from S3 - Retrieve files using signed URLs `M`
- [x] PDF to image conversion - Extract images using libvips/pdfium `L`
- [ ] Upload images to S3 - Stream converted images to destination `M`
- [ ] Webhook notifications - Send success/failure status with unique_id `S`
- [ ] Basic error handling - Return appropriate HTTP status codes `S`

### Dependencies

- AWS SAM environment setup
- LocalStack configuration
- Docker with libvips/pdfium installed

## Phase 2: Production Readiness

**Goal:** Add robustness, monitoring, and performance optimization
**Success Criteria:** Handle 100+ concurrent conversions with 99.9% success rate

### Features

- [ ] Async processing with SQS - Queue jobs for reliability `M`
- [ ] DynamoDB job tracking - Store job status and metadata `M`
- [ ] Retry logic - Automatic retry for transient failures `S`
- [ ] CloudWatch metrics - Track conversion times and success rates `S`
- [ ] Rate limiting - Protect against abuse `S`
- [ ] Multi-page batch optimization - Process pages in parallel `M`

### Dependencies

- Phase 1 completion
- AWS production account setup
- Monitoring dashboard configuration

## Phase 3: Advanced Features

**Goal:** Extend functionality beyond basic conversion
**Success Criteria:** Support multiple document operations via separate endpoints

### Features

- [ ] Text extraction endpoint - OCR capabilities for PDFs `L`
- [ ] Watermarking endpoint - Add watermarks to converted images `M`
- [ ] Thumbnail generation - Create preview images `M`
- [ ] Format options - Support PNG, JPEG, WebP outputs `S`
- [ ] Resolution options - Configurable DPI settings `S`
- [ ] Page range selection - Convert specific pages only `S`

### Dependencies

- Phase 2 completion
- Additional Lambda functions setup
- Extended API Gateway routes
# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-09-29-signed-s3-urls/spec.md

> Created: 2025-09-29
> Version: 1.0.0

## Technical Requirements

- **URL Validation**: Implement regex validation for S3 pre-signed URL format including required query parameters (X-Amz-Algorithm, X-Amz-Credential, X-Amz-Date, X-Amz-Expires, X-Amz-SignedHeaders, X-Amz-Signature)
- **HTTP Client Configuration**: Configure HTTP clients with appropriate timeouts (30s for downloads, 60s for uploads) and retry logic with exponential backoff for transient failures
- **Stream Processing**: Use streaming for PDF download and image upload to minimize memory usage, especially for large PDFs
- **Content-Type Handling**: Set appropriate content-type headers (application/pdf for downloads, image/png or image/jpeg for uploads)
- **Error Response Codes**: Return 400 for invalid URLs, 403 for access denied, 408 for expired URLs, 504 for timeout errors
- **Concurrent Upload Support**: Enable parallel upload of multiple converted images to destination URLs using thread pools
- **URL Expiration Check**: Pre-validate URL expiration times from X-Amz-Expires parameter before starting processing
- **Progress Tracking**: Implement progress callbacks for large file transfers to enable webhook status updates
- **Request Validation**: Validate that source URL uses GET method and destination URLs support PUT method
- **Security Headers**: Ensure all S3 requests include appropriate security headers and do not expose sensitive parameters in logs
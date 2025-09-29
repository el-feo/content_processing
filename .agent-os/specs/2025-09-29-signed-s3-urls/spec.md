# Spec Requirements Document

> Spec: Signed S3 URLs Support
> Created: 2025-09-29

## Overview

Implement support for pre-signed S3 URLs in the PDF converter service to enable secure, direct S3 access for source PDFs and destination images. This feature will allow clients to provide temporary, scoped S3 URLs in the request body, eliminating the need for the service to manage long-term S3 credentials and improving security through time-limited access.

## User Stories

### Enterprise Developer Integration

As an enterprise developer, I want to provide pre-signed S3 URLs for both source and destination, so that I can maintain control over S3 bucket access without sharing credentials.

The developer generates pre-signed URLs from their backend using AWS SDKs with appropriate expiration times (typically 15-60 minutes). They submit a conversion request with these URLs, and the service downloads the PDF from the source URL, converts it to images, and uploads the results to the destination URL. This workflow ensures that the conversion service never needs direct access to their S3 buckets, maintaining security boundaries and simplifying IAM permission management.

### SaaS Platform Batch Processing

As a SaaS platform operator, I want to process PDFs using pre-signed URLs with controlled lifetimes, so that I can implement secure, time-boxed conversion operations.

The platform generates batch conversion requests with pre-signed URLs that expire after processing windows. Each request includes URLs valid for the expected conversion duration plus buffer time. The service validates URL accessibility before accepting requests, providing immediate feedback if URLs are invalid. This enables reliable batch processing with clear failure modes and automatic cleanup of expired access.

## Spec Scope

1. **Pre-signed URL Validation** - Validate that provided S3 URLs are properly formatted and accessible before accepting conversion requests
2. **Source PDF Download** - Implement secure download of PDF files using pre-signed GET URLs with proper error handling
3. **Destination Image Upload** - Upload converted images to S3 using pre-signed PUT URLs with appropriate content types
4. **Error Handling Enhancement** - Handle URL expiration, access denied, and network errors with detailed error messages
5. **Request Schema Update** - Update API request/response schemas to clearly document signed URL requirements

## Out of Scope

- Generating pre-signed URLs within the service (clients must provide them)
- Managing S3 bucket policies or IAM roles
- Supporting non-S3 storage providers
- URL refreshing or renewal during long-running conversions

## Expected Deliverable

1. API endpoint accepts and validates pre-signed S3 URLs in source and destination fields
2. Service successfully downloads PDFs from pre-signed source URLs and uploads images to pre-signed destination URLs
3. Clear error messages returned for invalid, expired, or inaccessible URLs
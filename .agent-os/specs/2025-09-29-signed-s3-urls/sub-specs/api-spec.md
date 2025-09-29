# API Specification

This is the API specification for the spec detailed in @.agent-os/specs/2025-09-29-signed-s3-urls/spec.md

## Endpoints

### POST /convert

**Purpose:** Convert PDF to images using pre-signed S3 URLs for source and destination

**Request Body:**
```json
{
  "source": "https://bucket.s3.region.amazonaws.com/path/to/file.pdf?X-Amz-Algorithm=...&X-Amz-Signature=...",
  "destination": "https://bucket.s3.region.amazonaws.com/path/to/output/?X-Amz-Algorithm=...&X-Amz-Signature=...",
  "webhook": "https://example.com/webhook",
  "unique_id": "client-123"
}
```

**Parameters:**
- `source` (string, required): Pre-signed S3 URL with GET permissions for the source PDF
- `destination` (string, required): Pre-signed S3 URL with PUT permissions for the destination path
- `webhook` (string, optional): Callback URL for completion notification
- `unique_id` (string, required): Client-provided identifier for tracking

**Response (Success - 202 Accepted):**
```json
{
  "message": "PDF conversion request accepted",
  "unique_id": "client-123",
  "status": "accepted"
}
```

**Response (Validation Error - 400 Bad Request):**
```json
{
  "error": "Invalid S3 pre-signed URL format",
  "details": "Source URL missing required signature parameters",
  "unique_id": "client-123",
  "status": "error"
}
```

**Response (Access Error - 403 Forbidden):**
```json
{
  "error": "Access denied to S3 resource",
  "details": "Cannot access source URL: AccessDenied",
  "unique_id": "client-123",
  "status": "error"
}
```

**Errors:**
- `400 Bad Request`: Invalid URL format or missing required parameters
- `403 Forbidden`: Access denied to S3 resource
- `408 Request Timeout`: Pre-signed URL expired
- `422 Unprocessable Entity`: URL validation passed but resource inaccessible
- `500 Internal Server Error`: Processing failure

## Webhook Payload

**Success Notification:**
```json
{
  "unique_id": "client-123",
  "status": "completed",
  "images": [
    "https://bucket.s3.region.amazonaws.com/path/to/output/page-1.png",
    "https://bucket.s3.region.amazonaws.com/path/to/output/page-2.png"
  ],
  "page_count": 2,
  "processing_time_ms": 3456
}
```

**Failure Notification:**
```json
{
  "unique_id": "client-123",
  "status": "failed",
  "error": "URL expired during processing",
  "details": "Destination URL expired while uploading page 3",
  "processing_time_ms": 45678
}
```
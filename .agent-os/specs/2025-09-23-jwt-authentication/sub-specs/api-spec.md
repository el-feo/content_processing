# API Specification

This is the API specification for the spec detailed in @.agent-os/specs/2025-09-23-jwt-authentication/spec.md

## Endpoints

### GET /process

**Purpose:** Protected endpoint for PDF processing requests
**Headers:**

- Authorization: Bearer {JWT_TOKEN}
- Content-Type: application/json
**Parameters:**
- pdf_url (string): S3 URL or public URL of PDF to process
- output_format (string): Image format (png, jpg, webp)
- pages (array): Page numbers to convert (optional, defaults to all)
**Response:**

```json
{
  "job_id": "string",
  "status": "processing",
  "webhook_url": "string",
  "estimated_completion": "ISO8601 timestamp"
}
```

**Errors:**

- 401: Invalid or expired JWT token
- 403: Insufficient permissions for requested operation
- 400: Invalid request parameters

## Lambda Authorizer

### Authorization Handler

**Purpose:** Validate JWT tokens at API Gateway level
**Input Event:**

```json
{
  "authorizationToken": "Bearer {JWT_TOKEN}",
  "methodArn": "arn:aws:execute-api:region:account:api-id/stage/method/resource-path"
}
```

**Response (Allow):**

```json
{
  "principalId": "user_id",
  "policyDocument": {
    "Version": "2012-10-17",
    "Statement": [{
      "Action": "execute-api:Invoke",
      "Effect": "Allow",
      "Resource": "methodArn"
    }]
  },
  "context": {
    "user_id": "string",
    "permissions": "string",
    "expires_at": "timestamp"
  }
}
```

**Response (Deny):**

```json
{
  "principalId": "unauthorized",
  "policyDocument": {
    "Version": "2012-10-17",
    "Statement": [{
      "Action": "execute-api:Invoke",
      "Effect": "Deny",
      "Resource": "methodArn"
    }]
  }
}
```

## Error Response Format

All authentication and validation errors follow this structure:

```json
{
  "error": {
    "code": "AUTHENTICATION_FAILED",
    "message": "Invalid or expired token",
    "correlation_id": "uuid",
    "timestamp": "ISO8601"
  }
}
```

Error codes:

- AUTHENTICATION_FAILED: JWT validation failed
- TOKEN_EXPIRED: JWT token has expired
- INVALID_PERMISSIONS: User lacks required permissions
- VALIDATION_FAILED: Request payload validation failed

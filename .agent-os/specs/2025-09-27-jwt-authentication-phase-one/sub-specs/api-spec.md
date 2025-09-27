# API Specification

This is the API specification for the spec detailed in @.agent-os/specs/2025-09-27-jwt-authentication-phase-one/spec.md

> Created: 2025-09-27
> Version: 1.0.0

## Endpoints

All existing API endpoints will require JWT authentication. The authentication will be implemented as middleware that executes before the main endpoint logic.

### POST /convert

**Authentication Required**: Yes

**Request Headers:**

```
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

**Authentication Success - Existing Behavior:**

```json
{
  "message": "PDF conversion request received",
  "unique_id": "client-123",
  "status": "accepted"
}
```

**Authentication Failure Responses:**

**Missing Authorization Header:**

```
HTTP 401 Unauthorized
{
  "error": "Authorization header missing",
  "message": "Please provide a valid JWT token in the Authorization header"
}
```

**Invalid Bearer Format:**

```
HTTP 401 Unauthorized
{
  "error": "Invalid authorization format",
  "message": "Authorization header must be in format: Bearer <token>"
}
```

**Invalid JWT Token:**

```
HTTP 401 Unauthorized
{
  "error": "Invalid token",
  "message": "The provided JWT token is invalid or has expired"
}
```

**Secrets Manager Error:**

```
HTTP 500 Internal Server Error
{
  "error": "Authentication service unavailable",
  "message": "Unable to validate authentication at this time"
}
```

## Controllers

### Authentication Flow

1. **Token Extraction**: Extract JWT token from Authorization header
2. **Secret Retrieval**: Fetch JWT shared secret from AWS Secrets Manager (cached)
3. **Token Validation**: Validate JWT signature using shared secret
4. **Request Processing**: If valid, proceed to original endpoint logic
5. **Error Response**: If invalid, return appropriate HTTP 401/500 error

### JwtAuthenticator Class

**Methods:**

- `authenticate(event)`: Main authentication method that processes API Gateway event
- `extract_token(headers)`: Extract Bearer token from Authorization header
- `validate_token(token)`: Validate JWT token signature
- `get_secret()`: Retrieve and cache JWT secret from Secrets Manager

**Error Handling:**

- Graceful handling of malformed tokens
- Timeout handling for Secrets Manager calls
- Comprehensive logging of authentication failures

### Lambda Handler Integration

**Modified app.rb flow:**

```ruby
def lambda_handler(event:, context:)
  # 1. Authenticate request
  auth_result = JwtAuthenticator.authenticate(event)
  return auth_result unless auth_result[:success]

  # 2. Proceed with existing logic
  # ... existing PDF conversion logic
end
```

**Environment Variables:**

- `JWT_SECRET_NAME`: Name of the secret in AWS Secrets Manager
- `AWS_REGION`: AWS region for Secrets Manager access

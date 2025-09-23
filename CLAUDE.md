# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby-based AWS SAM (Serverless Application Model) application that implements a PDF-to-PNG conversion service using containerized Lambda functions. The service provides a REST API for processing PDF documents with JWT authentication, webhook notifications, and S3 integration.

## Development Commands

### Build and Deploy

```bash
sam build                    # Build the Docker image and prepare for deployment
sam deploy                   # Deploy using saved configuration
sam deploy --guided          # First-time deployment with prompts
```

### Local Development with LocalStack

```bash
# Start LocalStack services
docker-compose -f docker-compose.localstack.yml up -d

# Build and deploy to LocalStack
sam build
sam deploy --config-env localstack

# Test the service locally
./test_localstack.sh         # Full integration test with LocalStack
./quick_test_localstack.sh   # Quick test without webhook
./test_no_webhook.sh         # Test without webhook notifications
```

### Local API Testing

```bash
# Start API locally (requires JWT_SECRET environment variable)
JWT_SECRET='local-testing-secret-key' sam local start-api --env-vars env.json

# Test individual function
JWT_SECRET='local-testing-secret-key' sam local invoke PDFProcessorFunction --event events/pdf_process_event.json --env-vars env.json
```

### Testing

```bash
ruby tests/unit/test_handler.rb  # Run unit tests
```

### JWT Token Management

```bash
ruby scripts/generate_jwt.rb    # Generate JWT tokens for testing
ruby scripts/manage_secret.rb create    # Create secret in AWS Secrets Manager
ruby scripts/manage_secret.rb retrieve  # Retrieve secret from AWS Secrets Manager
```

### Monitoring

```bash
sam logs -n PDFProcessorFunction --stack-name content_processing --tail  # View Lambda logs
```

### Cleanup

```bash
sam delete --stack-name content_processing  # Delete the deployed stack
```

## Architecture

This is a serverless PDF processing service with the following key components:

### Core Application (`pdf_converter/app.rb`)
- **PDFProcessor**: Main handler class that orchestrates the entire processing workflow
- **URLValidator**: Validates and sanitizes S3 URLs and webhook endpoints for security
- **MetricsPublisher**: CloudWatch metrics integration for monitoring and alerting
- **JWT Authentication**: Secure API access using tokens stored in AWS Secrets Manager

### Infrastructure (`template.yaml`)
- **PDFProcessorFunction**: Lambda function with 3GB memory, 5-minute timeout, configured for PDF processing
- **API Gateway**: REST API with POST `/process` endpoint
- **AWS Secrets Manager**: Secure JWT secret storage with rotation capability
- **IAM Roles**: Least privilege access for Secrets Manager and CloudWatch

### Container Configuration (`pdf_converter/Dockerfile`)
- **Multi-stage build**: Separate build and runtime environments for optimized container size
- **libvips + pdfium**: High-performance PDF rendering with libvips for image processing
- **Amazon Linux 2023**: Base runtime with dnf package management
- **Library path configuration**: Proper linking for libvips and pdfium in Lambda environment

### Configuration Files
- **samconfig.toml**: Deployment configurations for both AWS and LocalStack environments
- **docker-compose.localstack.yml**: LocalStack setup for local development and testing
- **env.json**: Environment variables for local testing

### Processing Workflow
1. **Authentication**: JWT token validation against AWS Secrets Manager
2. **Input validation**: URL validation, size limits, security checks
3. **PDF download**: Streaming download with size limits and MIME type validation
4. **Concurrent processing**: Multi-threaded page conversion using configurable worker pools
5. **S3 upload**: Retry logic with exponential backoff for reliable uploads
6. **Webhook notifications**: Optional success/failure notifications with retry logic
7. **Cleanup**: Automatic temporary file cleanup

### Configuration Constants
- `MAX_PDF_SIZE`: 100MB file size limit
- `MAX_PAGES`: 100 page limit per PDF
- `PDF_DPI`: 150 DPI for image output
- `CONCURRENT_PAGES`: 5 concurrent page processing workers
- `WEBHOOK_TIMEOUT`: 10-second webhook timeout
- `WEBHOOK_RETRIES`: 3 retry attempts with exponential backoff

### Security Features
- S3 URL validation (only HTTPS S3 URLs allowed in production)
- Path traversal protection
- Internal network webhook blocking
- JWT-based authentication
- MIME type validation
- File size limits

### LocalStack Development
The application includes full LocalStack support for local development:
- S3 service emulation for file storage
- Secrets Manager emulation for JWT secrets
- CloudWatch emulation for metrics
- Docker networking for SAM local integration

### Testing Strategy
- **Unit tests**: Comprehensive mocking of AWS services and external dependencies
- **Integration tests**: LocalStack-based testing with real service interactions
- **Security tests**: URL validation, path traversal, authentication edge cases

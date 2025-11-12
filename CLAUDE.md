# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PDF Converter Service - A serverless PDF to image conversion service built with AWS SAM. This application provides secure, synchronous PDF processing with JWT authentication and optional webhook notifications. It uses containerized Ruby Lambda functions for scalable document processing.

## Initial Setup

For first-time deployment to AWS:

1. **Configure AWS CLI**: Run `aws configure` with your credentials
2. **Create JWT Secret**: Use AWS Secrets Manager to create `pdf-converter/jwt-secret`
   ```bash
   SECRET_VALUE=$(openssl rand -base64 32)
   aws secretsmanager create-secret --name pdf-converter/jwt-secret --secret-string "$SECRET_VALUE" --region us-east-1
   ```
3. **Deploy**: Run `sam build && sam deploy --guided`

See README.md for detailed setup instructions including JWT token generation and testing.

## Development Commands

### Build and Deploy

```bash
sam build                    # Build the Docker image and prepare for deployment
sam deploy                   # Deploy using saved configuration
sam deploy --guided          # First-time deployment with prompts
```

### Local Development

```bash
sam local start-api          # Run API locally on port 3000
sam local invoke PdfConverterFunction --event events/event.json  # Test function with sample event
```

### Testing

```bash
cd pdf_converter             # Navigate to Lambda function directory
bundle install               # Install dependencies including RSpec
bundle exec rspec           # Run RSpec tests
```

#### LocalStack Integration Testing

For local integration testing with LocalStack (requires LocalStack to be running):

```bash
# Start LocalStack (requires Docker)
docker run --rm -d -p 4566:4566 -p 4571:4571 localstack/localstack

# Run LocalStack integration tests
cd pdf_converter
LOCALSTACK_ENDPOINT=http://localhost:4566 \
AWS_ENDPOINT_URL=http://localhost:4566 \
AWS_REGION=us-east-1 \
bundle exec rspec spec/integration/localstack_integration_spec.rb --format documentation
```

LocalStack provides a local AWS cloud stack for testing AWS services without incurring costs or requiring AWS credentials.

### Monitoring

```bash
sam logs -n PdfConverterFunction --stack-name content_processing --tail  # View Lambda logs
```

### Cleanup

```bash
sam delete --stack-name content_processing  # Delete the deployed stack
```

## Architecture

The application follows AWS SAM patterns with containerized Ruby Lambda functions:

- **template.yaml**: Defines the serverless infrastructure including Lambda function configuration, API Gateway routes, and Docker packaging settings
- **pdf_converter/app.rb**: Main Lambda handler for PDF conversion with request validation and error handling
- **pdf_converter/Dockerfile**: Multi-stage Docker build using AWS Lambda Ruby base images
- **pdf_converter/Gemfile**: Ruby dependencies including JSON parsing, JWT authentication, and AWS SDK
- **samconfig.toml**: SAM CLI configuration with deployment settings including parallel builds and warm container support
- **events/**: Contains sample API Gateway proxy events for local testing
- **pdf_converter/spec/**: RSpec test suite for testing the PDF converter functionality
- **.agent-os/product/**: Product documentation including mission, roadmap, and technical decisions

The Lambda function is configured with:

- 2048 MB memory (optimized for PDF processing)
- 60-second timeout (to handle larger PDFs)
- Container packaging using Ruby 3.4
- API endpoint at `/convert` responding to POST requests

## API Specification

### POST /convert

Converts a PDF to images using temporary AWS credentials.

**Request Body:**

```json
{
  "source": {
    "bucket": "my-bucket",
    "key": "pdfs/document.pdf"
  },
  "destination": {
    "bucket": "my-bucket",
    "prefix": "converted/"
  },
  "credentials": {
    "accessKeyId": "ASIA...",
    "secretAccessKey": "...",
    "sessionToken": "..."
  },
  "unique_id": "client-123",
  "webhook": "https://example.com/webhook"
}
```

**Security Model:** The service uses temporary AWS STS credentials for S3 access:

- **Scoped permissions**: Credentials are limited to specific S3 buckets/prefixes
- **Time-limited access**: Credentials expire after 15 minutes
- **No long-term credentials**: No permanent AWS keys are stored or exposed
- **Client control**: Clients generate credentials by assuming their own IAM role
- **Preflight validation**: Service validates credentials before processing
- **Audit trail**: All S3 access is logged under the client's AWS account

**Response:**

```json
{
  "message": "PDF conversion and upload completed",
  "images": [
    "https://my-bucket.s3.amazonaws.com/converted/client-123-0.png",
    "https://my-bucket.s3.amazonaws.com/converted/client-123-1.png"
  ],
  "unique_id": "client-123",
  "status": "completed",
  "pages_converted": 2,
  "metadata": {
    "pdf_page_count": 2,
    "conversion_dpi": 300,
    "image_format": "png"
  }
}
```

**Note:** The service processes PDFs synchronously and returns the converted images in the response. If a webhook URL is provided, a notification is also sent asynchronously (fire-and-forget) upon completion.

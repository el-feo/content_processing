# PDF Converter Service

## 🚧 Under Construction

A serverless PDF to image conversion service built with AWS SAM. This application provides secure, synchronous PDF processing with JWT authentication and optional webhook notifications using containerized Ruby Lambda functions.

## Project Structure

- **pdf_converter/** - Code for the PDF conversion Lambda function and Docker configuration
  - **app/** - Application modules (JWT authenticator, URL validator, PDF converter, etc.)
  - **spec/** - RSpec test suite for the application
  - **lib/** - Shared library code
  - **Dockerfile** - Multi-stage Docker build configuration
  - **Gemfile** - Ruby dependencies
- **events/** - Sample invocation events for testing the function
- **template.yaml** - SAM template defining AWS resources
- **samconfig.toml** - SAM CLI deployment configuration

## Prerequisites

- [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)
- [Docker](https://hub.docker.com/search/?type=edition&offering=community)
- [Ruby 3.4](https://www.ruby-lang.org/en/documentation/installation/) (for local development)

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

## API Specification

### POST /convert

Converts a PDF to images.

**Request Body:**

```json
{
  "source": "https://s3.amazonaws.com/bucket/input.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=...",
  "destination": "https://s3.amazonaws.com/bucket/output/?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=...",
  "webhook": "https://example.com/webhook",
  "unique_id": "client-123"
}
```

**Important:** Both `source` and `destination` URLs must be pre-signed S3 URLs. Pre-signed URLs provide:

- **Enhanced security**: No AWS credentials are exposed in the Lambda function
- **Fine-grained access control**: URLs have time-limited access and specific permissions (GET for source, PUT for destination)
- **Client control**: Clients generate URLs with their own AWS credentials, maintaining data sovereignty
- **Audit trail**: All S3 access is logged under the client's AWS account

**Response:**

```json
{
  "message": "PDF conversion and upload completed",
  "images": [
    "https://s3.amazonaws.com/bucket/output/client-123-0.png?...",
    "https://s3.amazonaws.com/bucket/output/client-123-1.png?..."
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

## Architecture

The application follows AWS SAM patterns with containerized Ruby Lambda functions:

- **Lambda Function**: 2048 MB memory, 60-second timeout, Ruby 3.4 runtime
- **Authentication**: JWT-based authentication using AWS Secrets Manager
- **Packaging**: Container-based deployment using multi-stage Docker builds
- **API**: REST API via API Gateway with `/convert` endpoint

## Environment Variables

The Lambda function uses these environment variables:

- `JWT_SECRET_NAME`: Name of the secret in AWS Secrets Manager (defaults to pdf-converter/jwt-secret)
- `CONVERSION_DPI`: DPI resolution for PDF to image conversion (default: 300)
- `PNG_COMPRESSION`: PNG compression level 0-9 (default: 6)
- `MAX_PAGES`: Maximum number of pages allowed per PDF (default: 500)
- `VIPS_WARNING`: Controls libvips warning output (default: 0)
- `AWS_REGION`: AWS region for Secrets Manager (set by Lambda runtime, typically us-east-1)

## Dependencies

### Production

- **jwt (~> 2.7)**: JSON Web Token implementation for authentication
- **aws-sdk-secretsmanager (~> 1)**: AWS SDK for secure key retrieval
- **json (~> 2.9)**: JSON parsing and generation
- **ruby-vips (~> 2.2)**: Ruby bindings for libvips image processing library
- **async (~> 2.6)**: Asynchronous processing for batch uploads

### Testing

- **rspec (~> 3.12)**: Testing framework
- **webmock (~> 3.19)**: HTTP request stubbing for tests
- **aws-sdk-s3 (~> 1)**: AWS S3 SDK for integration tests
- **simplecov (~> 0.22)**: Code coverage analysis

### Development

- **rubocop (~> 1.81)**: Ruby code linter and formatter
- **rubycritic (~> 4.9)**: Code quality analysis tool

## Resources

- [AWS SAM Developer Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html)
- [AWS Serverless Application Repository](https://aws.amazon.com/serverless/serverlessrepo/)

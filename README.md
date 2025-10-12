# PDF Converter Service

A serverless PDF to image conversion service built with AWS SAM. This application provides secure, asynchronous PDF processing with JWT authentication and webhook notifications using containerized Ruby Lambda functions.

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
  "source": "https://s3.amazonaws.com/bucket/input.pdf",
  "destination": "https://s3.amazonaws.com/bucket/output/",
  "webhook": "https://example.com/webhook",
  "unique_id": "client-123"
}
```

**Response:**

```json
{
  "message": "PDF conversion request received",
  "unique_id": "client-123",
  "status": "accepted"
}
```

## Architecture

The application follows AWS SAM patterns with containerized Ruby Lambda functions:

- **Lambda Function**: 2048 MB memory, 60-second timeout, Ruby 3.4 runtime
- **Authentication**: JWT-based authentication using AWS Secrets Manager
- **Packaging**: Container-based deployment using multi-stage Docker builds
- **API**: REST API via API Gateway with `/convert` endpoint

## Environment Variables

The Lambda function uses these environment variables:

- `AWS_REGION`: AWS region for Secrets Manager (defaults to us-east-1)
- `JWT_SECRET_NAME`: Name of the secret in AWS Secrets Manager (defaults to pdf-converter/jwt-secret)

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
- **rubocop (~> 1.81)**: Ruby code linter and formatter

## Resources

- [AWS SAM Developer Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html)
- [AWS Serverless Application Repository](https://aws.amazon.com/serverless/serverlessrepo/)

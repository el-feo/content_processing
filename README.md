# PDF Converter Service

A Ruby-based AWS Lambda service that converts PDF documents to PNG images using libvips and pdfium. The service provides a REST API for PDF processing with JWT authentication and webhook notifications.

## Features

- **PDF to PNG Conversion**: High-quality conversion using libvips with pdfium backend
- **JWT Authentication**: Secure API access using AWS Secrets Manager
- **Webhook Notifications**: Optional callbacks on completion/failure
- **S3 Integration**: Direct upload to S3 with presigned URLs
- **Containerized Deployment**: Docker-based Lambda function for consistent runtime

## Project Structure

- `pdf_converter/` - Main Lambda function code and Dockerfile
- `events/` - Sample API Gateway events for testing
- `tests/` - Unit tests for the application
- `scripts/` - Utility scripts for JWT secret management
- `template.yaml` - AWS SAM infrastructure definition

## Prerequisites

- **AWS CLI** - [Install and configure AWS CLI](https://aws.amazon.com/cli/)
- **SAM CLI** - [Install the SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)
- **Docker** - [Install Docker](https://docs.docker.com/get-docker/) (required for containerized builds)
- **Ruby 3.4** (optional, for local testing) - [Install Ruby](https://www.ruby-lang.org/en/documentation/installation/)

### M4 MacBook Users

This project is configured for M4 MacBooks with Apple Silicon. The Docker builds use `--platform=linux/amd64` to ensure compatibility with AWS Lambda's x86_64 architecture.

## JWT Secret Management

Before deploying, you need to create a JWT secret for authentication:

```bash
# Generate a new JWT secret and store it in AWS Secrets Manager
ruby scripts/generate_jwt.rb

# Or manage secrets manually
ruby scripts/manage_secret.rb create
ruby scripts/manage_secret.rb retrieve
```

## Building and Deployment

### 1. Build the Application

```bash
# Build the Docker image and prepare for deployment
sam build

# The build process will:
# - Create a multi-stage Docker build with libvips and pdfium
# - Install Ruby dependencies from Gemfile
# - Configure library paths for Amazon Linux 2023
```

### 2. Deploy to AWS

For first-time deployment:

```bash
sam deploy --guided
```

For subsequent deployments:

```bash
sam deploy
```

#### Deployment Parameters

During guided deployment, you'll be prompted for:

- **Stack Name**: Unique CloudFormation stack name (e.g., `pdf-converter-prod`)
- **AWS Region**: Target AWS region
- **JWTSecretValue**: JWT secret for authentication (will be stored in Secrets Manager)
- **Confirm changes**: Review changes before deployment
- **Allow IAM role creation**: Required for Lambda execution and Secrets Manager access
- **Save parameters**: Save configuration to `samconfig.toml`

### 3. Get API Endpoint

After deployment, the API Gateway endpoint URL will be displayed in the output values.

## Local Development and Testing

### 1. Build Locally

```bash
sam build
```

The build process:
- Creates a Docker image with libvips, pdfium, and Ruby 3.4
- Installs gems from `pdf_converter/Gemfile`
- Configures library paths for Amazon Linux 2023 compatibility

### 2. Test the Lambda Function

Test with a sample PDF processing event:

```bash
# Test the PDF processor function with sample event
JWT_SECRET='local-testing-secret-key' sam local invoke PDFProcessorFunction --event events/pdf_process_event.json --env-vars env.json

# Or export the environment variable first
export JWT_SECRET='local-testing-secret-key'
sam local invoke PDFProcessorFunction --event events/pdf_process_event.json --env-vars env.json
```

### 3. Run API Locally

Start the API Gateway emulator:

```bash
sam local start-api --env-vars env.json
```

Then test the `/process` endpoint:

```bash
# Test with curl (requires valid JWT token)
curl -X POST http://localhost:3000/process \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"source":"https://example.com/sample.pdf","destination":"https://s3-bucket.s3.amazonaws.com/output/"}'
```

### 4. Generate Test JWT Tokens

```bash
# Generate a JWT token for testing
ruby scripts/generate_jwt.rb
```

## Testing

### Unit Tests

Run the test suite:

```bash
ruby tests/unit/test_handler.rb
```

The tests cover:
- JWT authentication validation
- Request payload validation
- Error handling scenarios
- Mock PDF processing workflow

### Integration Testing

Test the deployed function:

```bash
# View Lambda function logs in real-time
sam logs -n PDFProcessorFunction --stack-name your-stack-name --tail

# Test the deployed API endpoint
curl -X POST https://your-api-id.execute-api.region.amazonaws.com/Prod/process \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"source":"https://example.com/sample.pdf","destination":"https://s3-bucket.s3.amazonaws.com/output/"}'
```

## Troubleshooting

### M4 MacBook Build Issues

If you encounter platform-related build errors:

1. Ensure Docker is running
2. The Dockerfile uses `--platform=linux/amd64` for Lambda compatibility
3. Build process automatically handles Amazon Linux 2023 package management

### Library Loading Issues

If libvips fails to load:

1. The Dockerfile creates necessary symlinks for libvips
2. Library paths are configured in both Dockerfile and application code
3. Local testing uses the same Docker environment as deployment

### AWS Secrets Manager Issues

For authentication problems:

1. Ensure AWS credentials are configured: `aws configure`
2. Local testing falls back to `JWT_SECRET` environment variable
3. Use the provided scripts in `scripts/` for secret management

## API Usage

### Request Format

```json
{
  "source": "https://source-bucket.s3.amazonaws.com/input.pdf",
  "destination": "https://dest-bucket.s3.amazonaws.com/output/",
  "webhook": "https://your-app.com/webhook" // optional
}
```

### Response Format

```json
{
  "status": "success",
  "message": "PDF processed successfully",
  "images_count": 3,
  "image_urls": [
    "https://dest-bucket.s3.amazonaws.com/output/page_0001.png",
    "https://dest-bucket.s3.amazonaws.com/output/page_0002.png",
    "https://dest-bucket.s3.amazonaws.com/output/page_0003.png"
  ]
}
```

## Cleanup

To delete the deployed application and all AWS resources:

```bash
sam delete --stack-name your-stack-name
```

This will remove:
- Lambda function
- API Gateway
- IAM roles
- AWS Secrets Manager secret

## Architecture

The service uses:

- **AWS Lambda**: Containerized Ruby 3.4 runtime with 2GB memory and 5-minute timeout
- **API Gateway**: REST API with POST /process endpoint
- **AWS Secrets Manager**: Secure JWT secret storage
- **Docker**: Multi-stage build with libvips and pdfium
- **Amazon Linux 2023**: Base runtime with dnf package manager

## Resources

- [AWS SAM Developer Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html)
- [libvips Documentation](https://www.libvips.org/API/current/)
- [AWS Lambda Container Images](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)

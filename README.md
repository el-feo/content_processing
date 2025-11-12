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

## Getting Started

This guide walks you through deploying the PDF Converter Service to your AWS account from scratch.

### Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured with your AWS credentials
- [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html) installed
- [Docker](https://hub.docker.com/search/?type=edition&offering=community) installed and running
- [Ruby 3.4](https://www.ruby-lang.org/en/documentation/installation/) (optional, for local development)
- An AWS account with permissions to create Lambda functions, API Gateway, ECR repositories, and Secrets Manager secrets

### Step 1: Configure AWS CLI

If you haven't already, configure the AWS CLI with your credentials:

```bash
aws configure
```

Enter your AWS Access Key ID, Secret Access Key, default region (e.g., `us-east-1`), and output format (e.g., `json`).

### Step 2: Create JWT Secret

The service uses JWT authentication. Create a secret in AWS Secrets Manager to store your JWT signing key:

```bash
# Generate a secure random secret (256-bit recommended)
SECRET_VALUE=$(openssl rand -base64 32)

# Create the secret in AWS Secrets Manager
aws secretsmanager create-secret \
  --name pdf-converter/jwt-secret \
  --secret-string "$SECRET_VALUE" \
  --region us-east-1

# Save the secret value for later use in generating tokens
echo "Your JWT secret: $SECRET_VALUE"
```

**Important:** Save the secret value securely - you'll need it to generate JWT tokens for API authentication.

### Step 3: Clone and Deploy

Clone the repository and deploy using SAM:

```bash
# Clone the repository
git clone https://github.com/your-username/content_processing.git
cd content_processing

# Build the application
sam build

# Deploy (first time - this will prompt for configuration)
sam deploy --guided
```

During `sam deploy --guided`, you'll be prompted for:
- **Stack Name**: Press Enter to use default `content-processing`
- **AWS Region**: Enter your preferred region (e.g., `us-east-1`)
- **Confirm changes before deploy**: `Y` (recommended)
- **Allow SAM CLI IAM role creation**: `Y` (required)
- **Disable rollback**: `N` (recommended)
- **Save arguments to configuration file**: `Y` (saves settings for future deploys)

The deployment will:
1. Create an ECR repository for the Docker image
2. Build and push the container image
3. Create the Lambda function
4. Set up API Gateway with a `/convert` endpoint
5. Configure IAM roles and permissions

### Step 4: Get Your API Endpoint

After successful deployment, note the API endpoint URL from the outputs:

```
Outputs
-------------------------------------------------------------------
PdfConverterApi = https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/Prod/convert/
```

### Step 5: Generate JWT Tokens

To call the API, you need a valid JWT token. Here's how to generate one using Ruby:

```ruby
require 'jwt'

# Use the secret you created in Step 2
secret = 'your-secret-from-step-2'

# Generate a token that expires in 1 hour
payload = {
  sub: 'user-identifier',
  exp: Time.now.to_i + 3600
}

token = JWT.encode(payload, secret, 'HS256')
puts "Authorization: Bearer #{token}"
```

Or using Python:

```python
import jwt
import time

# Use the secret you created in Step 2
secret = 'your-secret-from-step-2'

# Generate a token that expires in 1 hour
payload = {
    'sub': 'user-identifier',
    'exp': int(time.time()) + 3600
}

token = jwt.encode(payload, secret, algorithm='HS256')
print(f"Authorization: Bearer {token}")
```

### Step 6: Set Up IAM Role for Testing

The API requires temporary AWS credentials to access your S3 buckets. Set up an IAM role:

```bash
./scripts/setup_iam_role.rb \
  --source-bucket your-bucket \
  --dest-bucket your-bucket
```

Note the role ARN from the output.

### Step 7: Test Your Deployment

Generate temporary credentials and call the API:

```bash
# 1. Generate JWT token
./scripts/generate_jwt_token.rb

# 2. Generate temporary AWS credentials
./scripts/generate_sts_credentials.rb \
  --role-arn arn:aws:iam::123456789012:role/PdfConverterClientRole

# 3. Call the API (replace with your values)
curl -X POST https://your-api-endpoint.amazonaws.com/Prod/convert \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "source": {
      "bucket": "your-bucket",
      "key": "pdfs/test.pdf"
    },
    "destination": {
      "bucket": "your-bucket",
      "prefix": "output/"
    },
    "credentials": {
      "accessKeyId": "ASIA...",
      "secretAccessKey": "...",
      "sessionToken": "..."
    },
    "unique_id": "test-123",
    "webhook": "https://your-webhook-endpoint.com/notify"
  }'
```

### Testing Scripts

To simplify testing, this repository includes utility scripts in the `scripts/` directory. The scripts automatically install their dependencies on first run using `bundler/inline` - no manual gem installation needed!

**Setup IAM Role (one-time):**
```bash
./scripts/setup_iam_role.rb \
  --source-bucket my-bucket \
  --dest-bucket my-bucket
```

**Generate JWT Token:**
```bash
./scripts/generate_jwt_token.rb
```

**Generate STS Credentials:**
```bash
./scripts/generate_sts_credentials.rb \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/PdfConverterClientRole
```

See [scripts/README.md](scripts/README.md) for detailed usage instructions and examples.

## Prerequisites (Local Development)

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

**Required Fields:**

- `source.bucket`: S3 bucket containing the PDF
- `source.key`: S3 object key for the PDF (must end with `.pdf`)
- `destination.bucket`: S3 bucket for converted images
- `destination.prefix`: S3 prefix (folder path) for images
- `credentials`: Temporary AWS STS credentials with:
  - `accessKeyId`: AWS access key (must start with `ASIA` or `AKIA`)
  - `secretAccessKey`: AWS secret access key
  - `sessionToken`: AWS session token
- `unique_id`: Unique identifier for this conversion (alphanumeric, underscores, and hyphens only)

**Optional Fields:**

- `webhook`: URL to receive completion notification

**Security Model:**

The service uses temporary AWS credentials (STS) for enhanced security:

- **Scoped permissions**: Credentials are limited to specific S3 buckets/prefixes
- **Time-limited access**: Credentials expire after 15 minutes
- **No long-term credentials**: No permanent AWS keys are stored or exposed
- **Client control**: Clients generate credentials by assuming their own IAM role
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

**Image Naming Convention:**

Converted images are stored with the format: `{prefix}{unique_id}-{page_number}.png`

Examples:
- `output/test-123-0.png` (first page)
- `output/test-123-1.png` (second page)

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
- **aws-sdk-s3 (~> 1)**: AWS S3 SDK for direct S3 access with temporary credentials
- **aws-sdk-secretsmanager (~> 1)**: AWS SDK for secure key retrieval
- **json (~> 2.9)**: JSON parsing and generation
- **ruby-vips (~> 2.2)**: Ruby bindings for libvips image processing library

### Testing

- **rspec (~> 3.12)**: Testing framework
- **webmock (~> 3.19)**: HTTP request stubbing for tests
- **simplecov (~> 0.22)**: Code coverage analysis

### Development

- **rubocop (~> 1.81)**: Ruby code linter and formatter
- **rubycritic (~> 4.9)**: Code quality analysis tool

## Resources

- [AWS SAM Developer Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html)
- [AWS Serverless Application Repository](https://aws.amazon.com/serverless/serverlessrepo/)

# Testing Scripts

Utility scripts to help test the PDF Converter API against your deployed production environment.

## Prerequisites

Install the required gems:

```bash
gem install aws-sdk-s3 aws-sdk-secretsmanager jwt
```

Ensure your AWS credentials are configured:

```bash
aws configure
```

## Scripts

### 1. Generate JWT Token

Generate a JWT token for API authentication:

```bash
./scripts/generate_jwt_token.rb
```

The script retrieves the JWT secret from AWS Secrets Manager and generates a valid token.

**Options:**

```bash
./scripts/generate_jwt_token.rb [options]

Options:
  -s, --secret SECRET              JWT secret (if not using AWS Secrets Manager)
  -n, --secret-name NAME           AWS Secrets Manager secret name (default: pdf-converter/jwt-secret)
  -r, --region REGION              AWS region (default: us-east-1)
  -e, --expiration SECONDS         Token expiration in seconds (default: 3600)
  -u, --subject SUBJECT            Token subject/user identifier (default: test-user)
  -h, --help                       Show help message
```

**Example:**

```bash
# Generate token with default settings
./scripts/generate_jwt_token.rb

# Generate token with 2-hour expiration
./scripts/generate_jwt_token.rb --expiration 7200

# Use a different secret name
./scripts/generate_jwt_token.rb --secret-name my-app/jwt-secret --region us-west-2
```

### 2. Generate Pre-signed S3 URLs

Generate pre-signed S3 URLs for source PDF and destination folder:

```bash
./scripts/generate_presigned_urls.rb \
  --bucket my-bucket \
  --source-key pdfs/test.pdf \
  --dest-prefix output/
```

**Required Arguments:**

- `--bucket BUCKET`: S3 bucket name
- `--source-key KEY`: S3 key for source PDF (e.g., 'pdfs/test.pdf')
- `--dest-prefix PREFIX`: S3 prefix for destination images (e.g., 'output/')

**Optional Arguments:**

```bash
  -r, --region REGION              AWS region (default: us-east-1)
  -e, --expiration SECONDS         URL expiration in seconds (default: 3600)
  -u, --unique-id ID               Unique ID for this conversion (default: test-TIMESTAMP)
  -f, --format FORMAT              Output format: pretty, json, curl (default: pretty)
  -h, --help                       Show help message
```

**Output Formats:**

- `pretty`: Human-readable output with JSON payload (default)
- `json`: JSON output for programmatic use
- `curl`: Ready-to-use curl command template

**Examples:**

```bash
# Generate URLs with pretty output
./scripts/generate_presigned_urls.rb \
  --bucket my-bucket \
  --source-key pdfs/sample.pdf \
  --dest-prefix converted/

# Generate URLs as JSON
./scripts/generate_presigned_urls.rb \
  --bucket my-bucket \
  --source-key pdfs/sample.pdf \
  --dest-prefix converted/ \
  --format json

# Generate URLs with curl template
./scripts/generate_presigned_urls.rb \
  --bucket my-bucket \
  --source-key pdfs/sample.pdf \
  --dest-prefix converted/ \
  --format curl

# Custom expiration and unique ID
./scripts/generate_presigned_urls.rb \
  --bucket my-bucket \
  --source-key pdfs/sample.pdf \
  --dest-prefix converted/ \
  --expiration 7200 \
  --unique-id my-test-123
```

## Complete Testing Workflow

Here's how to test your deployed API end-to-end:

### Step 1: Upload a test PDF to S3

```bash
aws s3 cp test.pdf s3://my-bucket/pdfs/test.pdf
```

### Step 2: Generate a JWT token

```bash
./scripts/generate_jwt_token.rb
```

Copy the token from the output.

### Step 3: Generate pre-signed URLs

```bash
./scripts/generate_presigned_urls.rb \
  --bucket my-bucket \
  --source-key pdfs/test.pdf \
  --dest-prefix output/
```

Copy the JSON payload from the output.

### Step 4: Call the API

Use the JWT token and JSON payload to call your deployed API:

```bash
curl -X POST https://your-api-id.execute-api.us-east-1.amazonaws.com/Prod/convert \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "https://s3.amazonaws.com/...",
    "destination": "https://s3.amazonaws.com/...",
    "unique_id": "test-123"
  }'
```

### Step 5: Check the results

```bash
# List converted images
aws s3 ls s3://my-bucket/output/

# Download an image to verify
aws s3 cp s3://my-bucket/output/test-123-0.png ./
```

## Troubleshooting

### AWS Credentials Not Found

Make sure you've configured AWS CLI:

```bash
aws configure
```

### Secret Not Found

Ensure the JWT secret exists in AWS Secrets Manager:

```bash
aws secretsmanager describe-secret --secret-id pdf-converter/jwt-secret
```

### Permission Denied

Your AWS user/role needs these permissions:
- `s3:GetObject` on the source bucket
- `s3:PutObject` on the destination bucket
- `secretsmanager:GetSecretValue` for the JWT secret

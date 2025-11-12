# Testing Scripts

Utility scripts to help test the PDF Converter API against your deployed production environment.

## Prerequisites

**Ruby**: The scripts require Ruby to be installed. They use `bundler/inline` to automatically install required gems on first run.

**AWS Credentials**: Ensure your AWS credentials are configured:

```bash
aws configure
```

The scripts will automatically install their dependencies (JWT, AWS SDK) when first run - no manual gem installation needed!

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

### 2. Setup IAM Role

Create an IAM role that clients can assume to access S3 buckets:

```bash
./scripts/setup_iam_role.rb \
  --source-bucket my-source-bucket \
  --dest-bucket my-dest-bucket
```

This script creates a role named `PdfConverterClientRole` with:
- Read permissions on source bucket(s)
- Write permissions on destination bucket(s)
- Trust policy requiring ExternalId `pdf-converter-client`

**Required Arguments:**

- `--source-bucket BUCKET`: Source S3 bucket (can specify multiple times)
- `--dest-bucket BUCKET`: Destination S3 bucket (can specify multiple times)

**Examples:**

```bash
# Create role with single source and destination bucket
./scripts/setup_iam_role.rb \
  --source-bucket my-pdfs \
  --dest-bucket my-images

# Create role with multiple buckets
./scripts/setup_iam_role.rb \
  --source-bucket bucket-1 \
  --source-bucket bucket-2 \
  --dest-bucket bucket-3
```

### 3. Generate STS Credentials

Generate temporary AWS credentials by assuming the IAM role:

```bash
./scripts/generate_sts_credentials.rb \
  --role-arn arn:aws:iam::123456789012:role/PdfConverterClientRole
```

The script assumes the role and returns temporary credentials (valid for 15 minutes) that can be used to call the API.

**Required Arguments:**

- `--role-arn ARN`: IAM role ARN to assume

**Optional Arguments:**

```bash
  -r, --region REGION              AWS region (default: us-east-1)
  -s, --session-name NAME          Role session name (default: pdf-converter-TIMESTAMP)
  -f, --format FORMAT              Output format: pretty, json, curl (default: pretty)
  -h, --help                       Show help message
```

**Output Formats:**

- `pretty`: Human-readable output with JSON payload (default)
- `json`: JSON output for programmatic use
- `curl`: Ready-to-use curl command template

**Examples:**

```bash
# Generate credentials with pretty output
./scripts/generate_sts_credentials.rb \
  --role-arn arn:aws:iam::123456789012:role/PdfConverterClientRole

# Generate credentials as JSON
./scripts/generate_sts_credentials.rb \
  --role-arn arn:aws:iam::123456789012:role/PdfConverterClientRole \
  --format json

# Generate curl command template
./scripts/generate_sts_credentials.rb \
  --role-arn arn:aws:iam::123456789012:role/PdfConverterClientRole \
  --format curl
```

## Complete Testing Workflow

Here's how to test your deployed API end-to-end:

### Step 1: Set up IAM Role (one-time setup)

Create an IAM role for testing:

```bash
./scripts/setup_iam_role.rb \
  --source-bucket my-bucket \
  --dest-bucket my-bucket
```

Note the role ARN from the output (e.g., `arn:aws:iam::123456789012:role/PdfConverterClientRole`).

### Step 2: Upload a test PDF to S3

```bash
aws s3 cp test.pdf s3://my-bucket/pdfs/test.pdf
```

### Step 3: Generate a JWT token

```bash
./scripts/generate_jwt_token.rb
```

Copy the token from the output.

### Step 4: Generate STS credentials

```bash
./scripts/generate_sts_credentials.rb \
  --role-arn arn:aws:iam::123456789012:role/PdfConverterClientRole
```

Copy the JSON payload from the output and update the bucket/key values.

### Step 5: Call the API

Use the JWT token and JSON payload to call your deployed API:

```bash
curl -X POST https://your-api-id.execute-api.us-east-1.amazonaws.com/Prod/convert \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "source": {
      "bucket": "my-bucket",
      "key": "pdfs/test.pdf"
    },
    "destination": {
      "bucket": "my-bucket",
      "prefix": "output/"
    },
    "credentials": {
      "accessKeyId": "ASIA...",
      "secretAccessKey": "...",
      "sessionToken": "..."
    },
    "unique_id": "test-123"
  }'
```

### Step 6: Check the results

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

### Unable to Assume Role

Ensure:
1. The role ARN is correct
2. Your AWS credentials have permission to assume the role
3. The role's trust policy includes your AWS account and the correct ExternalId

### Permission Denied

The temporary STS credentials need these permissions:
- `s3:GetObject` on the source bucket/key
- `s3:PutObject` on the destination bucket/prefix

These permissions are scoped to the IAM role and configured when you run `setup_iam_role.rb`.

# PDF Processor with LocalStack

This guide shows how to run and test the PDF processor service using LocalStack for local AWS service emulation.

## Prerequisites

- Docker and Docker Compose
- AWS CLI
- AWS SAM CLI
- Ruby (for JWT token generation)
- jq (optional, for JSON formatting)

```bash
# Install dependencies
pip install localstack  # LocalStack for AWS service emulation
gem install jwt         # Required for JWT token generation
brew install jq         # or apt-get install jq (optional, for JSON formatting)

# Note: Standard AWS CLI is used (not awslocal) with AWS_ENDPOINT_URL environment variable
```

## Quick Start

### 1. Start LocalStack and Test

```bash
# Run complete test cycle
./test_localstack.sh

# Or run individual steps:
./test_localstack.sh start   # Start LocalStack only
./test_localstack.sh test    # Test Lambda function
./test_localstack.sh stop    # Stop and cleanup
./test_localstack.sh logs    # View logs
```

### 2. Manual Setup

If you prefer manual setup:

```bash
# Start LocalStack
docker-compose -f docker-compose.localstack.yml up -d

# Wait for initialization
sleep 30

# Set environment variables
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Verify resources
aws s3 ls
aws secretsmanager list-secrets
```

## LocalStack Features

### Services Available

- **S3**: Object storage for PDFs and images
- **Lambda**: Function execution
- **Secrets Manager**: JWT secret storage
- **CloudWatch**: Metrics and logging
- **Logs**: Function logs

### Test Resources Created

- S3 buckets: `test-pdfs`, `test-output`
- Secret: `pdf-processor/jwt-secret`
- Test PDF: uploaded to `s3://test-pdfs/test.pdf`
- Webhook server: running on port 8080

## Testing the Function

### 1. Using SAM Local

```bash
# Build function
sam build

# Start Lambda locally with LocalStack network
sam local start-lambda \
  --host 0.0.0.0 \
  --port 3001 \
  --docker-network content_processing_localstack-net \
  --env-vars pdf_converter/env.json

# In another terminal, generate JWT token and invoke function
JWT_TOKEN=$(ruby -e "require 'jwt'; puts JWT.encode({sub: 'test', exp: Time.now.to_i + 3600}, 'localstack-secret-key', 'HS256')")

# Update event file with JWT token (or use test script which does this automatically)
sed "s/PLACEHOLDER_JWT_TOKEN/$JWT_TOKEN/g" events/localstack_event.json > /tmp/localstack_event_with_token.json

# Invoke function
curl -X POST http://localhost:3001/2015-03-31/functions/PDFProcessorFunction/invocations \
  -H "Content-Type: application/json" \
  -d @/tmp/localstack_event_with_token.json
```

### 2. Using Test Scripts (Recommended)

```bash
# Use the provided test scripts for easier testing
./test_localstack.sh full          # Complete test cycle
./quick_test_localstack.sh          # Quick test without webhook
./test_no_webhook.sh                # Test without webhook notifications

# Or step by step:
./test_localstack.sh start          # Start LocalStack only
./test_localstack.sh test           # Test Lambda function
./test_localstack.sh stop           # Stop and cleanup
./test_localstack.sh logs           # View logs
```

### 3. Manual AWS CLI Testing

```bash
# Generate JWT token (if testing manually)
JWT_TOKEN=$(ruby -e "require 'jwt'; puts JWT.encode({sub: 'test', exp: Time.now.to_i + 3600}, 'localstack-secret-key', 'HS256')")

# Set LocalStack endpoint and test with standard AWS CLI
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Test with standard AWS CLI (requires LocalStack deployment, not SAM local)
aws lambda invoke \
  --function-name PDFProcessorFunction \
  --payload "{\"body\":\"{\\\"source\\\":\\\"s3://test-pdfs/test.pdf\\\",\\\"destination\\\":\\\"s3://test-output/\\\"}\",\"headers\":{\"Authorization\":\"Bearer $JWT_TOKEN\"}}" \
  response.json
```

## Configuration

### Environment Variables

The function automatically detects LocalStack when:

- `LOCALSTACK_HOSTNAME` is set
- `AWS_ENDPOINT_URL` contains `localhost` or `4566`
- `AWS_SAM_LOCAL` environment variable is set

Environment files:

- `pdf_converter/env.json` - Local testing with SAM local
- `env-localstack.json` - LocalStack deployment configuration

### LocalStack-Specific Changes

1. **S3 URLs**: Automatically converted from `s3://bucket/key` to LocalStack endpoint
2. **Webhook URLs**: HTTP allowed (HTTPS normally required in production)
3. **Internal Networks**: Localhost and internal IPs allowed for webhooks
4. **AWS Services**: All point to LocalStack endpoint (`http://localhost:4566` or `http://host.docker.internal:4566` for SAM local)
5. **JWT Token Replacement**: Test scripts automatically replace `PLACEHOLDER_JWT_TOKEN` in event files

## Monitoring

### View Logs

```bash
# LocalStack logs
docker-compose -f docker-compose.localstack.yml logs -f

# Lambda logs
sam local start-lambda --debug

# Webhook logs
docker-compose -f docker-compose.localstack.yml logs webhook-server
```

### Check Resources

```bash
# Set LocalStack endpoint (if not already set)
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# List S3 objects
aws s3 ls s3://test-output/ --recursive

# View metrics (if enabled)
aws cloudwatch list-metrics --namespace PDFProcessor

# Check secrets
aws secretsmanager get-secret-value --secret-id pdf-processor/jwt-secret
```

## Troubleshooting

### Common Issues

1. **Port conflicts**: Ensure ports 4566, 8080, 3001 are available
2. **JWT errors**: Check secret is created and matches token
3. **Network issues**: Verify Docker network connectivity
4. **File permissions**: Ensure test script is executable

### Debug Commands

```bash
# Check LocalStack health
curl http://localhost:4566/_localstack/health

# Check Lambda function exists (set AWS_ENDPOINT_URL first)
aws lambda list-functions

# Verify Docker network
docker network ls | grep localstack

# Check container logs
docker logs pdf-processor-localstack
```

### Reset LocalStack

```bash
# Stop and remove all data
./test_localstack.sh stop
docker-compose -f docker-compose.localstack.yml down -v

# Restart fresh
./test_localstack.sh start
```

## Development Workflow

### Option 1: Full Test Script (Recommended)

1. **Complete test cycle**: `./test_localstack.sh full`
2. **Make code changes** in `pdf_converter/app.rb`
3. **Test changes**: `sam build && ./test_localstack.sh test`
4. **Check results** in S3 and webhook logs
5. **Iterate** as needed

### Option 2: Manual Step-by-Step

1. **Start LocalStack**: `./test_localstack.sh start`
2. **Build and test**: `sam build && ./test_localstack.sh test`
3. **View logs**: `./test_localstack.sh logs`
4. **Stop when done**: `./test_localstack.sh stop`

### Option 3: Quick Testing

1. **Quick test without webhook**: `./quick_test_localstack.sh`
2. **Test without webhook notifications**: `./test_no_webhook.sh`

## Integration with CI/CD

The LocalStack setup can be used in CI/CD pipelines:

```yaml
# Example GitHub Actions step
- name: Test with LocalStack
  run: |
    ./test_localstack.sh full
  env:
    DOCKER_BUILDKIT: 1
```

## Cost Benefits

- **No AWS charges** during development
- **Faster iteration** (no network latency)
- **Isolated testing** (no production impact)
- **Offline development** (works without internet)

## Next Steps

After testing locally:

1. **Deploy to AWS**: `sam deploy`
2. **Update environment**: Point to real AWS services
3. **Monitor production**: Use CloudWatch dashboards
4. **Scale as needed**: Adjust Lambda configuration

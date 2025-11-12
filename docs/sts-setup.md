# STS Credentials Setup Guide

This guide explains how to set up AWS Security Token Service (STS) credentials for the PDF Converter API.

## Table of Contents

- [Why STS Credentials?](#why-sts-credentials)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Using the API](#using-the-api)
- [Code Examples](#code-examples)
- [Troubleshooting](#troubleshooting)

## Why STS Credentials?

The PDF Converter API uses temporary AWS credentials (STS) instead of pre-signed URLs for several reasons:

**Security Benefits:**
- **Time-limited access**: Credentials expire after 15 minutes, limiting exposure window
- **No long-term credentials**: No permanent AWS keys are stored or transmitted
- **Scoped permissions**: Credentials are limited to specific S3 buckets and operations
- **Credential rotation**: Fresh credentials for each API call

**Operational Benefits:**
- **Client control**: You generate credentials in your own AWS account
- **Audit trail**: All S3 access appears in your CloudTrail logs
- **Flexible permissions**: Customize IAM policies to match your security requirements
- **No URL manipulation**: Direct S3 SDK access instead of HTTP requests

## Quick Start

For testing, use our utility scripts:

```bash
# 1. Create IAM role (one-time setup)
./scripts/setup_iam_role.rb \
  --source-bucket my-bucket \
  --dest-bucket my-bucket

# 2. Generate temporary credentials
./scripts/generate_sts_credentials.rb \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/PdfConverterClientRole

# 3. Use the credentials in your API request
```

## Detailed Setup

### Step 1: Create an IAM Role

Create an IAM role in your AWS account that the PDF Converter can assume.

**Using the AWS CLI:**

```bash
# 1. Create trust policy document
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::YOUR_ACCOUNT_ID:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "pdf-converter-client"
        }
      }
    }
  ]
}
EOF

# 2. Create the role
aws iam create-role \
  --role-name PdfConverterClientRole \
  --assume-role-policy-document file://trust-policy.json \
  --description "Role for PDF Converter client S3 access"

# 3. Create permissions policy
cat > permissions-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::my-source-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::my-dest-bucket/*"
    }
  ]
}
EOF

# 4. Attach permissions policy to role
aws iam put-role-policy \
  --role-name PdfConverterClientRole \
  --policy-name S3AccessPolicy \
  --policy-document file://permissions-policy.json
```

**Using our setup script:**

```bash
./scripts/setup_iam_role.rb \
  --source-bucket my-source-bucket \
  --dest-bucket my-dest-bucket
```

### Step 2: Assume the Role

To use the API, assume the role to get temporary credentials.

**Using AWS CLI:**

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/PdfConverterClientRole \
  --role-session-name pdf-converter-session \
  --external-id pdf-converter-client \
  --duration-seconds 900
```

**Using our script:**

```bash
./scripts/generate_sts_credentials.rb \
  --role-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/PdfConverterClientRole
```

The response contains temporary credentials:

```json
{
  "accessKeyId": "ASIA...",
  "secretAccessKey": "...",
  "sessionToken": "...",
  "expiration": "2025-01-11T12:30:00Z"
}
```

## Using the API

Once you have temporary credentials, include them in your API request:

```bash
curl -X POST https://api-endpoint.amazonaws.com/convert \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
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
    "unique_id": "conversion-123"
  }'
```

## Code Examples

### Ruby

```ruby
require 'aws-sdk-sts'
require 'net/http'
require 'json'

# Assume the IAM role
sts = Aws::STS::Client.new(region: 'us-east-1')
response = sts.assume_role(
  role_arn: 'arn:aws:iam::ACCOUNT_ID:role/PdfConverterClientRole',
  role_session_name: "pdf-converter-#{Time.now.to_i}",
  external_id: 'pdf-converter-client',
  duration_seconds: 900
)

credentials = response.credentials

# Call the PDF Converter API
uri = URI('https://api-endpoint.amazonaws.com/convert')
request = Net::HTTP::Post.new(uri)
request['Authorization'] = "Bearer #{jwt_token}"
request['Content-Type'] = 'application/json'
request.body = {
  source: {
    bucket: 'my-bucket',
    key: 'pdfs/document.pdf'
  },
  destination: {
    bucket: 'my-bucket',
    prefix: 'converted/'
  },
  credentials: {
    accessKeyId: credentials.access_key_id,
    secretAccessKey: credentials.secret_access_key,
    sessionToken: credentials.session_token
  },
  unique_id: 'conversion-123'
}.to_json

response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  http.request(request)
end

puts response.body
```

### Python

```python
import boto3
import requests
import json
from datetime import datetime

# Assume the IAM role
sts = boto3.client('sts', region_name='us-east-1')
response = sts.assume_role(
    RoleArn='arn:aws:iam::ACCOUNT_ID:role/PdfConverterClientRole',
    RoleSessionName=f'pdf-converter-{int(datetime.now().timestamp())}',
    ExternalId='pdf-converter-client',
    DurationSeconds=900
)

credentials = response['Credentials']

# Call the PDF Converter API
api_response = requests.post(
    'https://api-endpoint.amazonaws.com/convert',
    headers={
        'Authorization': f'Bearer {jwt_token}',
        'Content-Type': 'application/json'
    },
    json={
        'source': {
            'bucket': 'my-bucket',
            'key': 'pdfs/document.pdf'
        },
        'destination': {
            'bucket': 'my-bucket',
            'prefix': 'converted/'
        },
        'credentials': {
            'accessKeyId': credentials['AccessKeyId'],
            'secretAccessKey': credentials['SecretAccessKey'],
            'sessionToken': credentials['SessionToken']
        },
        'unique_id': 'conversion-123'
    }
)

print(api_response.json())
```

### Node.js

```javascript
const AWS = require('aws-sdk');
const axios = require('axios');

// Assume the IAM role
const sts = new AWS.STS({ region: 'us-east-1' });
const assumeRoleResponse = await sts.assumeRole({
  RoleArn: 'arn:aws:iam::ACCOUNT_ID:role/PdfConverterClientRole',
  RoleSessionName: `pdf-converter-${Date.now()}`,
  ExternalId: 'pdf-converter-client',
  DurationSeconds: 900
}).promise();

const credentials = assumeRoleResponse.Credentials;

// Call the PDF Converter API
const apiResponse = await axios.post(
  'https://api-endpoint.amazonaws.com/convert',
  {
    source: {
      bucket: 'my-bucket',
      key: 'pdfs/document.pdf'
    },
    destination: {
      bucket: 'my-bucket',
      prefix: 'converted/'
    },
    credentials: {
      accessKeyId: credentials.AccessKeyId,
      secretAccessKey: credentials.SecretAccessKey,
      sessionToken: credentials.SessionToken
    },
    unique_id: 'conversion-123'
  },
  {
    headers: {
      'Authorization': `Bearer ${jwtToken}`,
      'Content-Type': 'application/json'
    }
  }
);

console.log(apiResponse.data);
```

## Troubleshooting

### "Access Denied" when assuming role

**Cause**: Your AWS credentials don't have permission to assume the role.

**Solution**: Ensure your IAM user/role has the `sts:AssumeRole` permission:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::ACCOUNT_ID:role/PdfConverterClientRole"
    }
  ]
}
```

### "ExternalId mismatch"

**Cause**: The ExternalId in your AssumeRole request doesn't match the role's trust policy.

**Solution**: Always use `pdf-converter-client` as the ExternalId when assuming the role.

### "Access Denied" when downloading/uploading

**Cause**: The temporary credentials don't have the required S3 permissions.

**Solution**: Verify the role's permissions policy includes:
- `s3:GetObject` on source bucket
- `s3:PutObject` on destination bucket

### "Credentials have expired"

**Cause**: Temporary credentials expire after 15 minutes.

**Solution**: Generate fresh credentials before each API call. Implement credential caching and renewal in your application:

```ruby
class CredentialManager
  def initialize(role_arn)
    @role_arn = role_arn
    @credentials = nil
    @expiration = nil
  end

  def get_credentials
    # Refresh if expired or expiring soon (within 1 minute)
    if @credentials.nil? || Time.now >= (@expiration - 60)
      refresh_credentials
    end
    @credentials
  end

  private

  def refresh_credentials
    sts = Aws::STS::Client.new
    response = sts.assume_role(
      role_arn: @role_arn,
      role_session_name: "pdf-converter-#{Time.now.to_i}",
      external_id: 'pdf-converter-client',
      duration_seconds: 900
    )

    @credentials = {
      accessKeyId: response.credentials.access_key_id,
      secretAccessKey: response.credentials.secret_access_key,
      sessionToken: response.credentials.session_token
    }
    @expiration = response.credentials.expiration
  end
end
```

### "Invalid bucket name" or "Invalid key"

**Cause**: Bucket names or keys don't meet AWS S3 requirements.

**Solution**: Ensure:
- Bucket names are 3-63 characters, lowercase, numbers, dots, hyphens
- Keys are not empty and under 1024 characters
- Source keys end with `.pdf`

## Security Best Practices

1. **Scope permissions narrowly**: Only grant access to specific buckets/prefixes needed
2. **Use separate roles per application**: Don't share roles between different services
3. **Monitor CloudTrail logs**: Review AssumeRole calls and S3 access patterns
4. **Rotate ExternalId periodically**: Update the ExternalId in both the trust policy and your code
5. **Implement retry logic**: Handle credential expiration gracefully in your application
6. **Don't log credentials**: Never log the secretAccessKey or sessionToken

## Additional Resources

- [AWS STS Documentation](https://docs.aws.amazon.com/STS/latest/APIReference/welcome.html)
- [IAM Roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html)
- [AssumeRole API](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)
- [ExternalId Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html)

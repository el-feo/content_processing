# Implementation Plan: STS Credentials for S3 Access

## Overview

Replace pre-signed URLs with AWS STS temporary credentials. Clients assume an IAM role via STS and pass temporary credentials to Lambda, which uses them to access both source PDFs and upload converted images.

## Architecture

### Current (Broken) Flow
1. Client generates pre-signed GET URL for source PDF
2. Client generates pre-signed PUT URL for destination "prefix"
3. Lambda downloads PDF using source URL
4. Lambda modifies destination URL path (invalidates signature) ❌
5. Lambda uploads images (fails due to invalid signature) ❌

### New STS Flow
1. Client assumes IAM role via STS (gets temporary credentials)
2. Client sends: source bucket/key, destination bucket/prefix, temp credentials
3. Lambda uses temp credentials to create S3 client
4. Lambda downloads PDF from source bucket/key
5. Lambda uploads images to destination bucket/prefix
6. Credentials expire after 15-60 minutes

## Benefits

✅ **Works for any number of pages** - No pre-signing individual files
✅ **Client maintains control** - They scope the IAM policy
✅ **Simpler than current approach** - No pre-signed URL manipulation
✅ **Time-limited access** - Credentials auto-expire
✅ **Fixes existing bug** - No signature invalidation

---

## Phase 1: AWS Infrastructure Setup

### 1.1 Create IAM Role for PDF Conversion

**Role Name**: `PdfConverterClientRole`

**Trust Policy** (allows clients to assume the role):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:root"
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
```

**Permissions Policy** (attached to role):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadSourcePDFs",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${SourceBucket}/${SourcePrefix}*"
    },
    {
      "Sid": "WriteConvertedImages",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${DestinationBucket}/${DestinationPrefix}*"
    }
  ]
}
```

**Note**: Clients can further scope permissions when assuming the role using session policies.

### 1.2 CloudFormation Template Addition

Update `template.yaml` to include the IAM role (optional - clients can create their own):

```yaml
Resources:
  PdfConverterClientRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: PdfConverterClientRole
      Description: Role for clients to access S3 for PDF conversion
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: !Sub 'arn:aws:iam::${AWS::AccountId}:root'
            Action: 'sts:AssumeRole'
            Condition:
              StringEquals:
                'sts:ExternalId': 'pdf-converter-client'
      Policies:
        - PolicyName: S3AccessPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Sid: ReadSourcePDFs
                Effect: Allow
                Action: 's3:GetObject'
                Resource: 'arn:aws:s3:::*/*'
              - Sid: WriteConvertedImages
                Effect: Allow
                Action: 's3:PutObject'
                Resource: 'arn:aws:s3:::*/*'

Outputs:
  PdfConverterClientRoleArn:
    Description: ARN of the IAM role for clients
    Value: !GetAtt PdfConverterClientRole.Arn
    Export:
      Name: !Sub '${AWS::StackName}-ClientRoleArn'
```

---

## Phase 2: API Specification Changes

### 2.1 New Request Format

**Endpoint**: `POST /convert`

**Headers**:
- `Authorization: Bearer <JWT_TOKEN>` (unchanged)
- `Content-Type: application/json`

**Request Body**:
```json
{
  "source": {
    "bucket": "my-input-bucket",
    "key": "pdfs/document.pdf"
  },
  "destination": {
    "bucket": "my-output-bucket",
    "prefix": "converted/project-123/"
  },
  "credentials": {
    "accessKeyId": "ASIAIOSFODNN7EXAMPLE",
    "secretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    "sessionToken": "FQoGZXIvYXdzEPT//////////..."
  },
  "webhook": "https://example.com/webhook",
  "unique_id": "client-123"
}
```

**Response** (unchanged):
```json
{
  "message": "PDF conversion and upload completed",
  "images": [
    "s3://my-output-bucket/converted/project-123/page-1.png",
    "s3://my-output-bucket/converted/project-123/page-2.png"
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

### 2.2 Backward Compatibility (Optional)

Support both old (pre-signed URL) and new (STS) formats during transition:

```ruby
# Detect format based on request body structure
if request_body['credentials']
  # New STS format
  process_with_sts(request_body)
elsif request_body['source'].start_with?('https://')
  # Old pre-signed URL format (deprecated)
  process_with_presigned_urls(request_body)
end
```

---

## Phase 3: Lambda Function Changes

### 3.1 New Request Validator

**File**: `pdf_converter/app/request_validator.rb`

Add validation for new request format:

```ruby
def validate_sts_request(request_body)
  errors = []

  # Validate source
  source = request_body['source']
  if source.nil? || !source.is_a?(Hash)
    errors << 'source must be an object with bucket and key'
  else
    errors << 'source.bucket is required' if source['bucket'].nil? || source['bucket'].empty?
    errors << 'source.key is required' if source['key'].nil? || source['key'].empty?
  end

  # Validate destination
  destination = request_body['destination']
  if destination.nil? || !destination.is_a?(Hash)
    errors << 'destination must be an object with bucket and prefix'
  else
    errors << 'destination.bucket is required' if destination['bucket'].nil? || destination['bucket'].empty?
    errors << 'destination.prefix is required' if destination['prefix'].nil? || destination['prefix'].empty?
  end

  # Validate credentials
  credentials = request_body['credentials']
  if credentials.nil? || !credentials.is_a?(Hash)
    errors << 'credentials object is required'
  else
    errors << 'credentials.accessKeyId is required' if credentials['accessKeyId'].nil?
    errors << 'credentials.secretAccessKey is required' if credentials['secretAccessKey'].nil?
    errors << 'credentials.sessionToken is required' if credentials['sessionToken'].nil?
  end

  # Validate unique_id
  if request_body['unique_id'].nil? || request_body['unique_id'].empty?
    errors << 'unique_id is required'
  end

  errors
end
```

### 3.2 New PDF Downloader

**File**: `pdf_converter/app/pdf_downloader.rb`

Replace HTTP download with S3 SDK:

```ruby
class PdfDownloader
  def initialize(credentials = nil)
    @credentials = credentials
  end

  # Download PDF from S3 using credentials
  def download_from_s3(bucket, key)
    s3_client = create_s3_client

    response = s3_client.get_object(
      bucket: bucket,
      key: key
    )

    {
      success: true,
      content: response.body.read,
      metadata: {
        content_type: response.content_type,
        content_length: response.content_length
      }
    }
  rescue Aws::S3::Errors::NoSuchKey
    { success: false, error: 'Source PDF not found' }
  rescue Aws::S3::Errors::AccessDenied
    { success: false, error: 'Access denied to source PDF' }
  rescue Aws::Errors::ServiceError => e
    { success: false, error: "S3 error: #{e.message}" }
  rescue StandardError => e
    { success: false, error: "Download failed: #{e.message}" }
  end

  private

  def create_s3_client
    if @credentials
      Aws::S3::Client.new(
        access_key_id: @credentials['accessKeyId'],
        secret_access_key: @credentials['secretAccessKey'],
        session_token: @credentials['sessionToken']
      )
    else
      # Fall back to default credentials (Lambda IAM role)
      Aws::S3::Client.new
    end
  end
end
```

### 3.3 Update Image Uploader

**File**: `pdf_converter/app/image_uploader.rb`

Add S3 upload method:

```ruby
class ImageUploader
  def initialize(credentials = nil)
    @credentials = credentials
    @logger = Logger.new($stdout) if defined?(Logger)
  end

  # Upload images to S3 using credentials
  def upload_images_to_s3(bucket, prefix, image_paths)
    s3_client = create_s3_client
    uploaded_keys = []

    image_paths.each_with_index do |image_path, index|
      key = "#{prefix}page-#{index + 1}.png"

      s3_client.put_object(
        bucket: bucket,
        key: key,
        body: File.read(image_path, mode: 'rb'),
        content_type: 'image/png'
      )

      uploaded_keys << "s3://#{bucket}/#{key}"
      log_info("Uploaded #{key}")
    end

    {
      success: true,
      uploaded_urls: uploaded_keys
    }
  rescue Aws::S3::Errors::AccessDenied
    { success: false, error: 'Access denied to destination bucket' }
  rescue Aws::Errors::ServiceError => e
    { success: false, error: "S3 upload error: #{e.message}" }
  rescue StandardError => e
    { success: false, error: "Upload failed: #{e.message}" }
  end

  private

  def create_s3_client
    if @credentials
      Aws::S3::Client.new(
        access_key_id: @credentials['accessKeyId'],
        secret_access_key: @credentials['secretAccessKey'],
        session_token: @credentials['sessionToken']
      )
    else
      Aws::S3::Client.new
    end
  end
end
```

### 3.4 Update Main Handler

**File**: `pdf_converter/app.rb`

Update to use new format:

```ruby
def process_pdf_conversion(request_body, start_time, response_builder)
  unique_id = request_body['unique_id']
  output_dir = "/tmp/#{unique_id}"
  credentials = request_body['credentials']

  puts "Authentication successful for unique_id: #{unique_id}"

  # Download PDF from S3
  downloader = PdfDownloader.new(credentials)
  download_result = downloader.download_from_s3(
    request_body['source']['bucket'],
    request_body['source']['key']
  )
  return handle_failure(download_result, response_builder, 'PDF download', output_dir) unless download_result[:success]

  pdf_content = download_result[:content]
  puts "PDF downloaded successfully, size: #{pdf_content.bytesize} bytes"

  # Convert PDF to images (unchanged)
  conversion_result = PdfConverter.new.convert_to_images(
    pdf_content: pdf_content,
    output_dir: output_dir,
    unique_id: unique_id,
    dpi: ENV['CONVERSION_DPI']&.to_i || 300
  )
  unless conversion_result[:success]
    return handle_failure(conversion_result, response_builder, 'PDF conversion', output_dir)
  end

  images = conversion_result[:images]
  page_count = images.size
  puts "PDF converted successfully: #{page_count} pages"

  # Upload images to S3
  uploader = ImageUploader.new(credentials)
  upload_result = uploader.upload_images_to_s3(
    request_body['destination']['bucket'],
    request_body['destination']['prefix'],
    images
  )
  return handle_failure(upload_result, response_builder, 'Image upload', output_dir) unless upload_result[:success]

  uploaded_urls = upload_result[:uploaded_urls]
  puts "Images uploaded successfully: #{uploaded_urls.size} files"

  # Send webhook notification (unchanged)
  notify_webhook(request_body['webhook'], unique_id, uploaded_urls, page_count, start_time)

  # Clean up and return success
  FileUtils.rm_rf(output_dir)
  response_builder.success_response(
    unique_id: unique_id,
    uploaded_urls: uploaded_urls,
    page_count: page_count,
    metadata: conversion_result[:metadata]
  )
end
```

### 3.5 Security: Credential Sanitization

**File**: `pdf_converter/lib/credential_sanitizer.rb` (new)

```ruby
module CredentialSanitizer
  # Sanitize credentials for logging
  def self.sanitize(credentials)
    return nil unless credentials

    {
      'accessKeyId' => mask_credential(credentials['accessKeyId']),
      'secretAccessKey' => '***REDACTED***',
      'sessionToken' => mask_credential(credentials['sessionToken'])
    }
  end

  private

  def self.mask_credential(value)
    return nil unless value
    return '***REDACTED***' if value.length < 8

    "#{value[0..3]}...#{value[-4..]}"
  end
end
```

Add to all logging:
```ruby
puts "Using credentials: #{CredentialSanitizer.sanitize(credentials)}"
```

---

## Phase 4: Testing Scripts Updates

### 4.1 New STS Credential Generator

**File**: `scripts/generate_sts_credentials.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'aws-sdk-sts', '~> 1'
end

require 'optparse'
require 'json'

options = {
  role_arn: nil,
  duration: 3600,
  external_id: 'pdf-converter-client',
  source_bucket: nil,
  source_prefix: nil,
  dest_bucket: nil,
  dest_prefix: nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on("-r", "--role-arn ARN", "IAM Role ARN to assume") { |v| options[:role_arn] = v }
  opts.on("-d", "--duration SECONDS", Integer, "Credential duration (default: 3600)") { |v| options[:duration] = v }
  opts.on("--source-bucket BUCKET", "Source S3 bucket") { |v| options[:source_bucket] = v }
  opts.on("--source-prefix PREFIX", "Source S3 prefix") { |v| options[:source_prefix] = v }
  opts.on("--dest-bucket BUCKET", "Destination S3 bucket") { |v| options[:dest_bucket] = v }
  opts.on("--dest-prefix PREFIX", "Destination S3 prefix") { |v| options[:dest_prefix] = v }
  opts.on("-h", "--help", "Show help") do
    puts opts
    exit
  end
end.parse!

# Create STS client
sts = Aws::STS::Client.new

# Build session policy to scope permissions
session_policy = {
  "Version" => "2012-10-17",
  "Statement" => []
}

if options[:source_bucket]
  prefix = options[:source_prefix] || ''
  session_policy["Statement"] << {
    "Effect" => "Allow",
    "Action" => "s3:GetObject",
    "Resource" => "arn:aws:s3:::#{options[:source_bucket]}/#{prefix}*"
  }
end

if options[:dest_bucket]
  prefix = options[:dest_prefix] || ''
  session_policy["Statement"] << {
    "Effect" => "Allow",
    "Action" => "s3:PutObject",
    "Resource" => "arn:aws:s3:::#{options[:dest_bucket]}/#{prefix}*"
  }
end

# Assume role
response = sts.assume_role({
  role_arn: options[:role_arn],
  role_session_name: "pdf-converter-#{Time.now.to_i}",
  duration_seconds: options[:duration],
  external_id: options[:external_id],
  policy: session_policy.to_json
})

credentials = response.credentials

puts JSON.pretty_generate({
  accessKeyId: credentials.access_key_id,
  secretAccessKey: credentials.secret_access_key,
  sessionToken: credentials.session_token,
  expiration: credentials.expiration
})
```

### 4.2 Update API Test Script

**File**: `scripts/test_api.rb` (new)

Complete end-to-end testing script:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'aws-sdk-sts', '~> 1'
  gem 'aws-sdk-s3', '~> 1'
  gem 'jwt', '~> 2.7'
  gem 'aws-sdk-secretsmanager', '~> 1'
  gem 'rexml'
end

require 'net/http'
require 'json'
require 'optparse'

# Parse options...
# Generate STS credentials...
# Generate JWT token...
# Make API request...
# Display results...
```

---

## Phase 5: Documentation Updates

### 5.1 Update README.md

**Section: Getting Started > Step 1.5: Create IAM Role**

Add between "Create JWT Secret" and "Clone and Deploy":

```markdown
### Step 2.5: Create IAM Role for S3 Access

Create an IAM role that clients will assume to access S3:

\`\`\`bash
# Create the role with trust policy
aws iam create-role \
  --role-name PdfConverterClientRole \
  --assume-role-policy-document file://trust-policy.json

# Attach permissions policy
aws iam put-role-policy \
  --role-name PdfConverterClientRole \
  --policy-name S3AccessPolicy \
  --policy-document file://permissions-policy.json
\`\`\`

See [docs/sts-setup.md](docs/sts-setup.md) for detailed IAM policy examples.
```

### 5.2 Update API Specification

**Section: API Specification > POST /convert**

Replace request body example with new format.

### 5.3 Create STS Setup Guide

**File**: `docs/sts-setup.md` (new)

Comprehensive guide for:
- Creating IAM roles
- Configuring trust relationships
- Scoping permissions
- Testing with AWS CLI
- Troubleshooting

---

## Phase 6: Testing & Validation

### 6.1 Unit Tests

**New test files**:
- `spec/app/pdf_downloader_sts_spec.rb`
- `spec/app/image_uploader_sts_spec.rb`
- `spec/app/request_validator_sts_spec.rb`

### 6.2 Integration Tests

**File**: `spec/integration/sts_integration_spec.rb`

Test with LocalStack or real AWS:
- Assume role
- Download PDF
- Convert
- Upload images
- Verify results

### 6.3 Security Tests

- Expired credentials
- Invalid credentials
- Insufficient permissions
- Credential leakage in logs

---

## Phase 7: Deployment & Migration

### 7.1 Deployment Steps

1. Deploy updated Lambda function
2. Deploy IAM role via CloudFormation
3. Update API documentation
4. Notify clients of new format
5. Monitor for errors

### 7.2 Migration Strategy

**Option A: Hard cutover** (if no existing users)
- Deploy new version
- Update all documentation

**Option B: Gradual migration** (if existing users)
- Support both formats during transition period
- Add deprecation warnings for old format
- Set sunset date for pre-signed URL format
- Remove old code after sunset

---

## Timeline Estimate

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| 1. AWS Infrastructure | IAM role, policies, CloudFormation | 2 hours |
| 2. API Changes | Request validation, specs | 1 hour |
| 3. Lambda Changes | Downloader, uploader, handler | 4 hours |
| 4. Testing Scripts | STS generator, test script | 2 hours |
| 5. Documentation | README, API docs, STS guide | 3 hours |
| 6. Testing | Unit, integration, security | 4 hours |
| 7. Deployment | Deploy, monitor, validate | 2 hours |
| **Total** | | **18 hours** |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Credential leakage in logs | High | Sanitize all logging, security audit |
| Invalid credentials break service | Medium | Comprehensive validation, clear error messages |
| Performance impact | Low | STS overhead is minimal (~100ms) |
| Backward compatibility | Medium | Support both formats during transition |
| Client adoption complexity | Medium | Excellent documentation, example scripts |

---

## Success Criteria

✅ Lambda can download PDFs using STS credentials
✅ Lambda can upload images using STS credentials
✅ All unit tests pass
✅ Integration tests pass with real AWS
✅ No credentials logged
✅ Documentation updated
✅ Testing scripts work end-to-end
✅ API returns proper S3 URLs for uploaded images

---

## Next Steps

1. **Review this plan** - Get approval on approach
2. **Create feature branch** - `feature/sts-credentials`
3. **Implement Phase 1** - AWS infrastructure
4. **Implement Phases 2-3** - API and Lambda changes
5. **Implement Phase 4** - Testing scripts
6. **Implement Phase 5** - Documentation
7. **Execute Phase 6** - Testing
8. **Execute Phase 7** - Deployment

---

## Questions for Consideration

1. **Should we support both formats during transition?**
   - Yes if existing users, No if greenfield

2. **Who creates the IAM role - us or clients?**
   - Template includes example role
   - Clients can customize per their security requirements

3. **Should we validate credential permissions before processing?**
   - Could do a preflight check (HeadObject on source)
   - Trade-off: adds latency vs. fails faster

4. **What's the recommended credential expiration time?**
   - Suggest 15-60 minutes
   - Must be longer than max conversion time

5. **Should webhook notification include S3 URLs or signed URLs?**
   - S3 URLs (s3://bucket/key) - client controls access
   - Or HTTPS URLs - requires client has public access

---

## References

- [AWS STS AssumeRole Documentation](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)
- [AWS SDK for Ruby - S3](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html)
- [IAM Roles for Temporary Credentials](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use.html)
- [Session Policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html#policies_session)

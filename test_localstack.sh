#!/bin/bash
set -e

# LocalStack endpoint
LOCALSTACK_ENDPOINT="http://localhost:4566"
BUCKET_NAME="pdf-converter-test"
SECRET_NAME="pdf-converter/jwt-secret"
JWT_SECRET="test-secret-key-for-localstack-testing-12345"

echo "🚀 Setting up LocalStack environment for PDF Converter testing..."

# 1. Create S3 bucket
echo "📦 Creating S3 bucket: $BUCKET_NAME"
aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 mb s3://$BUCKET_NAME 2>/dev/null || echo "Bucket already exists"

# 2. Create JWT secret in Secrets Manager
echo "🔐 Creating JWT secret in Secrets Manager"
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --secret-string "$JWT_SECRET" 2>/dev/null || \
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager update-secret \
  --secret-id "$SECRET_NAME" \
  --secret-string "$JWT_SECRET"

# 3. Create a simple test PDF
echo "📄 Creating test PDF"
cat > /tmp/test.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Test PDF</title></head>
<body>
  <h1>PDF Conversion Test</h1>
  <p>This is page 1 of the test PDF.</p>
  <div style="page-break-after: always;"></div>
  <h1>Page 2</h1>
  <p>This is page 2 of the test PDF.</p>
</body>
</html>
EOF

# Convert HTML to PDF using wkhtmltopdf or similar (if available)
if command -v wkhtmltopdf &> /dev/null; then
  wkhtmltopdf /tmp/test.html /tmp/test.pdf
  echo "✅ PDF created with wkhtmltopdf"
elif command -v pandoc &> /dev/null; then
  pandoc /tmp/test.html -o /tmp/test.pdf
  echo "✅ PDF created with pandoc"
else
  # Create a minimal PDF if no tools available
  echo "⚠️  No PDF creation tools found. Creating minimal PDF with printf..."
  # This creates a minimal PDF with one page
  printf "%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>>>endobj\nxref\n0 4\n0000000000 65535 f\n0000000009 00000 n\n0000000052 00000 n\n0000000101 00000 n\ntrailer<</Size 4/Root 1 0 R>>\nstartxref\n178\n%%%%EOF" > /tmp/test.pdf
fi

# 4. Upload test PDF to LocalStack S3
echo "⬆️  Uploading test PDF to S3"
aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 cp /tmp/test.pdf s3://$BUCKET_NAME/input/test.pdf

# 5. Generate presigned URLs
echo "🔗 Generating presigned URLs"
SOURCE_URL=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 presign s3://$BUCKET_NAME/input/test.pdf --expires-in 3600)
DEST_URL=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 presign s3://$BUCKET_NAME/output/ --expires-in 3600)

echo ""
echo "✅ LocalStack setup complete!"
echo ""
echo "Source URL: $SOURCE_URL"
echo "Destination URL: $DEST_URL"
echo ""

# 6. Generate JWT token for authentication
echo "🔑 Generating JWT token..."

# Create a Ruby script to generate JWT token
cat > /tmp/generate_jwt.rb <<'RUBY'
require 'jwt'
require 'json'

secret = ARGV[0] || 'test-secret-key-for-localstack-testing-12345'

payload = {
  sub: 'test-client',
  iat: Time.now.to_i,
  exp: Time.now.to_i + 3600,
  service: 'pdf-converter'
}

token = JWT.encode(payload, secret, 'HS256')
puts token
RUBY

JWT_TOKEN=$(ruby /tmp/generate_jwt.rb "$JWT_SECRET")

echo "JWT Token: $JWT_TOKEN"
echo ""

# 7. Create test event for Lambda
echo "📝 Creating test event for Lambda invocation"
cat > /tmp/localstack_event.json <<EOF
{
  "body": "{\"source\":\"$SOURCE_URL\",\"destination\":\"$DEST_URL\",\"webhook\":\"http://localhost:3000/webhook\",\"unique_id\":\"test-123\"}",
  "headers": {
    "Authorization": "Bearer $JWT_TOKEN",
    "Content-Type": "application/json"
  },
  "httpMethod": "POST",
  "path": "/convert",
  "requestContext": {
    "requestId": "test-request-id"
  }
}
EOF

echo "✅ Test event created at /tmp/localstack_event.json"
echo ""
echo "🧪 To test the Lambda function locally with LocalStack:"
echo ""
echo "1. Set environment variables:"
echo "   export AWS_ENDPOINT_URL=$LOCALSTACK_ENDPOINT"
echo "   export AWS_REGION=us-east-1"
echo "   export JWT_SECRET_NAME=$SECRET_NAME"
echo ""
echo "2. Run the Lambda function:"
echo "   sam local invoke PdfConverterFunction --event /tmp/localstack_event.json --docker-network bridge --parameter-overrides 'ParameterKey=Environment,ParameterValue=local'"
echo ""
echo "Or use this simplified command:"
echo "   AWS_ENDPOINT_URL=$LOCALSTACK_ENDPOINT sam local invoke PdfConverterFunction --event /tmp/localstack_event.json"
echo ""
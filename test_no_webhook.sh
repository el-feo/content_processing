#!/bin/bash

# Quick LocalStack test without webhook

# Generate JWT token
JWT_TOKEN=$(ruby -e "require 'jwt'; puts JWT.encode({sub: 'test-user', exp: Time.now.to_i + 3600}, 'localstack-secret-key', 'HS256')")

echo "JWT Token: $JWT_TOKEN"

# Create event without webhook
cat > /tmp/test_no_webhook.json << EOF
{
  "body": "{\"source\":\"s3://test-pdfs/test.pdf\",\"destination\":\"s3://test-output/\"}",
  "headers": {
    "Authorization": "Bearer $JWT_TOKEN"
  },
  "httpMethod": "POST",
  "path": "/process"
}
EOF

# Run with SAM local invoke
sam local invoke PDFProcessorFunction \
  --event /tmp/test_no_webhook.json \
  --env-vars pdf_converter/env.json

echo "Test completed!"
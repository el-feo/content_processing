#!/bin/bash

# Quick LocalStack test

# Generate JWT token
JWT_TOKEN=$(ruby -e "require 'jwt'; puts JWT.encode({sub: 'test-user', exp: Time.now.to_i + 3600}, 'localstack-secret-key', 'HS256')")

echo "JWT Token: $JWT_TOKEN"

# Create event
cat > /tmp/quick_test.json << EOF
{
  "body": "{\"source\":\"s3://test-pdfs/test.pdf\",\"destination\":\"s3://test-output/\",\"webhook\":\"http://localhost:8080/webhook\"}",
  "headers": {
    "Authorization": "Bearer $JWT_TOKEN"
  },
  "httpMethod": "POST",
  "path": "/process"
}
EOF

# Create container env vars file
cat > /tmp/container_env.json << EOF
{
  "PDFProcessorFunction": {
    "JWT_SECRET": "localstack-secret-key",
    "LOCAL_TESTING": "true"
  }
}
EOF

# Run with SAM local invoke
sam local invoke PDFProcessorFunction \
  --event /tmp/quick_test.json \
  --env-vars pdf_converter/env.json \
  --container-env-vars /tmp/container_env.json

echo "Test completed!"
#!/bin/bash

# LocalStack PDF Processor Test Script - Using Existing LocalStack
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LOCALSTACK_ENDPOINT="http://localhost:4566"
AWS_ACCESS_KEY_ID="test"
AWS_SECRET_ACCESS_KEY="test"
AWS_DEFAULT_REGION="us-east-1"
JWT_SECRET="localstack-secret-key"

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to check if LocalStack is running
check_localstack() {
    log "Checking if LocalStack is running..."
    if curl -s "$LOCALSTACK_ENDPOINT/_localstack/health" > /dev/null 2>&1; then
        success "LocalStack is running!"
        return 0
    else
        error "LocalStack is not running. Please start it with: localstack start"
        exit 1
    fi
}

# Function to generate JWT token
generate_jwt_token() {
    log "Generating JWT token..."
    JWT_TOKEN=$(ruby -e "
        require 'jwt'
        payload = {
            sub: 'localstack-test-user',
            exp: Time.now.to_i + 3600,
            iat: Time.now.to_i
        }
        puts JWT.encode(payload, '$JWT_SECRET', 'HS256')
    " 2>/dev/null || echo "")

    if [ -z "$JWT_TOKEN" ]; then
        error "Failed to generate JWT token. Make sure Ruby and JWT gem are installed."
        echo "Install with: gem install jwt"
        exit 1
    fi
    success "JWT token generated"
}

# Function to update event file with JWT token
update_event_file() {
    log "Updating event file with JWT token..."
    sed "s/PLACEHOLDER_JWT_TOKEN/$JWT_TOKEN/g" events/localstack_event.json > /tmp/localstack_event_with_token.json
    success "Event file updated"
}

# Function to setup LocalStack resources
setup_resources() {
    log "Setting up LocalStack resources..."

    # Set AWS CLI to use LocalStack
    export AWS_ENDPOINT_URL=$LOCALSTACK_ENDPOINT
    export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION

    # Create S3 buckets
    log "Creating S3 buckets..."
    aws s3 mb s3://test-pdfs 2>/dev/null || warning "Bucket test-pdfs already exists"
    aws s3 mb s3://test-output 2>/dev/null || warning "Bucket test-output already exists"

    # Create/update secret
    log "Creating JWT secret..."
    aws secretsmanager create-secret \
        --name pdf-processor/jwt-secret \
        --secret-string "{\"jwt_secret\":\"$JWT_SECRET\"}" 2>/dev/null || \
    (warning "Secret exists, updating..." && \
     aws secretsmanager update-secret \
        --secret-id pdf-processor/jwt-secret \
        --secret-string "{\"jwt_secret\":\"$JWT_SECRET\"}")

    # Create test PDF
    log "Creating test PDF..."
    cat > /tmp/test.pdf << 'EOF'
%PDF-1.4
1 0 obj
<<
/Type /Catalog
/Pages 2 0 R
>>
endobj
2 0 obj
<<
/Type /Pages
/Kids [3 0 R]
/Count 1
>>
endobj
3 0 obj
<<
/Type /Page
/Parent 2 0 R
/MediaBox [0 0 612 792]
/Contents 4 0 R
>>
endobj
4 0 obj
<<
/Length 44
>>
stream
BT
/F1 12 Tf
100 700 Td
(Test PDF) Tj
ET
endstream
endobj
xref
0 5
0000000000 65535 f
0000000010 00000 n
0000000079 00000 n
0000000173 00000 n
0000000301 00000 n
trailer
<<
/Size 5
/Root 1 0 R
>>
startxref
394
%%EOF
EOF

    # Upload test PDF
    aws s3 cp /tmp/test.pdf s3://test-pdfs/test.pdf
    success "Test PDF uploaded"

    # Clean up temp file
    rm -f /tmp/test.pdf

    success "LocalStack resources setup completed"
}

# Function to start webhook server
start_webhook_server() {
    log "Starting webhook server..."

    # Check if already running
    if lsof -i :8080 > /dev/null 2>&1; then
        warning "Port 8080 is in use. Webhook server may already be running."
        return 0
    fi

    # Start Python webhook server in background
    python3 -c "
import http.server
import socketserver
import json
from datetime import datetime

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)

        print(f'[{datetime.now()}] Webhook received:')
        print(f'Body: {post_data.decode()}')

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{\"status\": \"received\"}')

    def log_message(self, format, *args):
        pass

with socketserver.TCPServer(('', 8080), WebhookHandler) as httpd:
    print('Webhook server running on port 8080')
    httpd.serve_forever()
" > /tmp/webhook_server.log 2>&1 &

    WEBHOOK_PID=$!
    echo $WEBHOOK_PID > /tmp/webhook.pid

    sleep 2
    success "Webhook server started (PID: $WEBHOOK_PID)"
}

# Function to test the Lambda function
test_lambda() {
    log "Testing Lambda function..."

    # Build SAM application
    log "Building SAM application..."
    sam build

    # Start SAM local Lambda with environment variables
    log "Starting SAM local Lambda..."

    # Create environment file for LocalStack
    cat > /tmp/env-localstack.json << EOF
{
  "PDFProcessorFunction": {
    "JWT_SECRET_NAME": "pdf-processor/jwt-secret",
    "JWT_SECRET": "$JWT_SECRET",
    "LOCAL_TESTING": "true",
    "AWS_SAM_LOCAL": "true",
    "AWS_REGION": "us-east-1",
    "AWS_ENDPOINT_URL": "http://host.docker.internal:4566",
    "LOCALSTACK_HOSTNAME": "localstack",
    "MAX_PDF_SIZE": "104857600",
    "MAX_PAGES": "100",
    "PDF_DPI": "150",
    "CONCURRENT_PAGES": "5",
    "WEBHOOK_TIMEOUT": "10",
    "WEBHOOK_RETRIES": "3"
  }
}
EOF

    # Start Lambda in background
    sam local start-lambda \
        --host 0.0.0.0 \
        --port 3001 \
        --env-vars /tmp/env-localstack.json &

    LAMBDA_PID=$!
    echo $LAMBDA_PID > /tmp/lambda.pid

    # Wait for Lambda to start
    log "Waiting for Lambda to start..."
    sleep 10

    # Update event for localhost webhook
    cat > /tmp/test_event.json << EOF
{
  "body": "{\"source\":\"s3://test-pdfs/test.pdf\",\"destination\":\"s3://test-output/\",\"webhook\":\"http://host.docker.internal:8080/webhook\"}",
  "headers": {
    "Authorization": "Bearer $JWT_TOKEN"
  },
  "httpMethod": "POST",
  "path": "/process",
  "requestContext": {
    "requestId": "test-$(date +%s)"
  }
}
EOF

    # Invoke Lambda
    log "Invoking Lambda function..."
    RESPONSE=$(curl -s -X POST \
        http://localhost:3001/2015-03-31/functions/PDFProcessorFunction/invocations \
        -H "Content-Type: application/json" \
        -d @/tmp/test_event.json)

    echo "Lambda Response:"
    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"

    # Check response
    if echo "$RESPONSE" | grep -q "statusCode"; then
        STATUS_CODE=$(echo "$RESPONSE" | jq -r '.statusCode' 2>/dev/null || echo "unknown")
        if [ "$STATUS_CODE" = "200" ]; then
            success "Lambda function executed successfully!"
        else
            warning "Lambda returned status: $STATUS_CODE"
            echo "Body: $(echo "$RESPONSE" | jq -r '.body' 2>/dev/null)"
        fi
    else
        error "Lambda did not respond correctly"
    fi

    # Check webhook log
    if [ -f /tmp/webhook_server.log ]; then
        log "Webhook server log:"
        tail -5 /tmp/webhook_server.log
    fi
}

# Function to cleanup
cleanup() {
    log "Cleaning up..."

    # Stop Lambda
    if [ -f /tmp/lambda.pid ]; then
        LAMBDA_PID=$(cat /tmp/lambda.pid)
        if kill -0 $LAMBDA_PID 2>/dev/null; then
            kill $LAMBDA_PID
            success "Lambda stopped"
        fi
        rm -f /tmp/lambda.pid
    fi

    # Stop webhook server
    if [ -f /tmp/webhook.pid ]; then
        WEBHOOK_PID=$(cat /tmp/webhook.pid)
        if kill -0 $WEBHOOK_PID 2>/dev/null; then
            kill $WEBHOOK_PID
            success "Webhook server stopped"
        fi
        rm -f /tmp/webhook.pid
    fi

    # Clean up temp files
    rm -f /tmp/localstack_event_with_token.json
    rm -f /tmp/test_event.json
    rm -f /tmp/env-localstack.json
    rm -f /tmp/webhook_server.log

    success "Cleanup completed"
}

# Main execution
main() {
    log "Starting LocalStack PDF Processor Test (using existing LocalStack)"

    # Check dependencies
    command -v ruby >/dev/null 2>&1 || { error "Ruby is required"; exit 1; }
    command -v sam >/dev/null 2>&1 || { error "SAM CLI is required"; exit 1; }
    command -v aws >/dev/null 2>&1 || { error "AWS CLI is required"; exit 1; }

    # Check LocalStack
    check_localstack

    # Generate JWT
    generate_jwt_token
    update_event_file

    case "${1:-test}" in
        "setup")
            setup_resources
            ;;
        "webhook")
            start_webhook_server
            echo "Webhook server running. Press Ctrl+C to stop."
            wait
            ;;
        "test")
            setup_resources
            start_webhook_server
            test_lambda
            ;;
        "cleanup")
            cleanup
            ;;
        *)
            echo "Usage: $0 {setup|webhook|test|cleanup}"
            echo "  setup   - Setup LocalStack resources"
            echo "  webhook - Start webhook server only"
            echo "  test    - Run complete test (default)"
            echo "  cleanup - Stop services and cleanup"
            exit 1
            ;;
    esac

    success "Test completed!"
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main
main "$@"
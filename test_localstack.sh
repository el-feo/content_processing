#!/bin/bash

# LocalStack PDF Processor Test Script
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

# Function to wait for LocalStack
wait_for_localstack() {
    log "Waiting for LocalStack to be ready..."
    for i in {1..30}; do
        if curl -s "$LOCALSTACK_ENDPOINT/_localstack/health" > /dev/null 2>&1; then
            success "LocalStack is ready!"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    error "LocalStack failed to start within 60 seconds"
    exit 1
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

# Function to start LocalStack
start_localstack() {
    log "Starting LocalStack with Docker Compose..."

    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose not found. Please install Docker Compose."
        exit 1
    fi

    # Start LocalStack
    docker-compose -f docker-compose.localstack.yml up -d

    # Wait for services to be ready
    wait_for_localstack

    # Wait for initialization to complete
    log "Waiting for LocalStack initialization to complete..."
    sleep 10

    # Check if services are initialized
    log "Checking LocalStack services..."
    docker-compose -f docker-compose.localstack.yml logs pdf-processor-init
}

# Function to verify LocalStack resources
verify_resources() {
    log "Verifying LocalStack resources..."

    # Set AWS CLI to use LocalStack
    export AWS_ENDPOINT_URL=$LOCALSTACK_ENDPOINT
    export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION

    # Check S3 buckets
    if aws s3 ls | grep -q "test-pdfs"; then
        success "S3 bucket 'test-pdfs' exists"
    else
        warning "Creating S3 bucket 'test-pdfs'..."
        aws s3 mb s3://test-pdfs
    fi

    if aws s3 ls | grep -q "test-output"; then
        success "S3 bucket 'test-output' exists"
    else
        warning "Creating S3 bucket 'test-output'..."
        aws s3 mb s3://test-output
    fi

    # Check secret
    if aws secretsmanager describe-secret --secret-id pdf-processor/jwt-secret > /dev/null 2>&1; then
        success "JWT secret exists"
    else
        warning "Creating JWT secret..."
        aws secretsmanager create-secret \
            --name pdf-processor/jwt-secret \
            --secret-string "{\"jwt_secret\":\"$JWT_SECRET\"}"
    fi

    # Check if test PDF exists
    if aws s3 ls s3://test-pdfs/test.pdf > /dev/null 2>&1; then
        success "Test PDF exists"
    else
        warning "Uploading test PDF..."
        echo "%PDF-1.4 Test PDF content" > /tmp/test.pdf
        aws s3 cp /tmp/test.pdf s3://test-pdfs/test.pdf
        rm /tmp/test.pdf
    fi
}

# Function to build and deploy Lambda
deploy_lambda() {
    log "Building SAM application..."
    sam build

    log "Starting SAM local Lambda..."
    export AWS_ENDPOINT_URL=$LOCALSTACK_ENDPOINT
    export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION

    # Start SAM local in background
    sam local start-lambda \
        --host 0.0.0.0 \
        --port 3001 \
        --docker-network content_processing_localstack-net \
        --env-vars pdf_converter/env.json &

    LAMBDA_PID=$!
    echo $LAMBDA_PID > /tmp/lambda.pid

    # Wait for Lambda to start
    log "Waiting for Lambda to start..."
    sleep 10

    success "Lambda is running (PID: $LAMBDA_PID)"
}

# Function to test the Lambda function
test_lambda() {
    log "Testing Lambda function..."

    # Test with LocalStack event
    log "Invoking Lambda with LocalStack event..."

    RESPONSE=$(curl -s -X POST \
        http://localhost:3001/2015-03-31/functions/PDFProcessorFunction/invocations \
        -H "Content-Type: application/json" \
        -d @/tmp/localstack_event_with_token.json)

    echo "Lambda Response:"
    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"

    # Check if response contains expected fields
    if echo "$RESPONSE" | grep -q "statusCode"; then
        success "Lambda function responded"

        # Check status code
        STATUS_CODE=$(echo "$RESPONSE" | jq -r '.statusCode' 2>/dev/null || echo "unknown")
        if [ "$STATUS_CODE" = "200" ]; then
            success "Lambda function executed successfully"
        else
            warning "Lambda function returned status code: $STATUS_CODE"
            echo "Response body:"
            echo "$RESPONSE" | jq -r '.body' 2>/dev/null || echo "$RESPONSE"
        fi
    else
        error "Lambda function did not respond correctly"
        echo "Response: $RESPONSE"
    fi
}

# Function to check webhook
check_webhook() {
    log "Checking webhook server logs..."
    docker-compose -f docker-compose.localstack.yml logs webhook-server | tail -20
}

# Function to cleanup
cleanup() {
    log "Cleaning up..."

    # Stop Lambda
    if [ -f /tmp/lambda.pid ]; then
        LAMBDA_PID=$(cat /tmp/lambda.pid)
        if kill -0 $LAMBDA_PID 2>/dev/null; then
            log "Stopping Lambda (PID: $LAMBDA_PID)..."
            kill $LAMBDA_PID
        fi
        rm -f /tmp/lambda.pid
    fi

    # Clean up temp files
    rm -f /tmp/localstack_event_with_token.json

    success "Cleanup completed"
}

# Function to stop LocalStack
stop_localstack() {
    log "Stopping LocalStack..."
    docker-compose -f docker-compose.localstack.yml down
    success "LocalStack stopped"
}

# Main execution
main() {
    log "Starting LocalStack PDF Processor Test"

    # Check dependencies
    log "Checking dependencies..."
    command -v ruby >/dev/null 2>&1 || { error "Ruby is required but not installed."; exit 1; }
    command -v sam >/dev/null 2>&1 || { error "AWS SAM CLI is required but not installed."; exit 1; }
    command -v aws >/dev/null 2>&1 || { error "AWS CLI is required but not installed."; exit 1; }
    command -v jq >/dev/null 2>&1 || { warning "jq not found. JSON responses may not be formatted."; }

    # Generate JWT token
    generate_jwt_token
    update_event_file

    case "${1:-full}" in
        "start")
            start_localstack
            verify_resources
            ;;
        "test")
            verify_resources
            deploy_lambda
            test_lambda
            check_webhook
            cleanup
            ;;
        "stop")
            cleanup
            stop_localstack
            ;;
        "full")
            start_localstack
            verify_resources
            deploy_lambda
            test_lambda
            check_webhook
            cleanup
            ;;
        "logs")
            docker-compose -f docker-compose.localstack.yml logs -f
            ;;
        *)
            echo "Usage: $0 {start|test|stop|full|logs}"
            echo "  start - Start LocalStack and verify resources"
            echo "  test  - Deploy and test Lambda function"
            echo "  stop  - Stop LocalStack and cleanup"
            echo "  full  - Complete test cycle (default)"
            echo "  logs  - Show LocalStack logs"
            exit 1
            ;;
    esac

    success "Test completed successfully!"
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
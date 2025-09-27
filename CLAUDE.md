# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PDF Converter Service - A serverless PDF to image conversion service built with AWS SAM. This application provides secure, asynchronous PDF processing with JWT authentication and webhook notifications. It uses containerized Ruby Lambda functions for scalable document processing.

## Development Commands

### Build and Deploy

```bash
sam build                    # Build the Docker image and prepare for deployment
sam deploy                   # Deploy using saved configuration
sam deploy --guided          # First-time deployment with prompts
```

### Local Development

```bash
sam local start-api          # Run API locally on port 3000
sam local invoke PdfConverterFunction --event events/event.json  # Test function with sample event
```

### Testing

```bash
cd pdf_converter             # Navigate to Lambda function directory
bundle install               # Install dependencies including RSpec
bundle exec rspec           # Run RSpec tests
```

### Monitoring

```bash
sam logs -n PdfConverterFunction --stack-name content_processing --tail  # View Lambda logs
```

### Cleanup

```bash
sam delete --stack-name content_processing  # Delete the deployed stack
```

## Architecture

The application follows AWS SAM patterns with containerized Ruby Lambda functions:

- **template.yaml**: Defines the serverless infrastructure including Lambda function configuration, API Gateway routes, and Docker packaging settings
- **pdf_converter/app.rb**: Main Lambda handler for PDF conversion with request validation and error handling
- **pdf_converter/Dockerfile**: Multi-stage Docker build using AWS Lambda Ruby base images
- **pdf_converter/Gemfile**: Ruby dependencies including JSON parsing, JWT authentication, and AWS SDK
- **samconfig.toml**: SAM CLI configuration with deployment settings including parallel builds and warm container support
- **events/**: Contains sample API Gateway proxy events for local testing
- **pdf_converter/spec/**: RSpec test suite for testing the PDF converter functionality
- **.agent-os/product/**: Product documentation including mission, roadmap, and technical decisions

The Lambda function is configured with:

- 2048 MB memory (optimized for PDF processing)
- 60-second timeout (to handle larger PDFs)
- Container packaging using Ruby 3.4
- API endpoint at `/convert` responding to POST requests

## API Specification

### POST /convert

Converts a PDF to images.

**Request Body:**
```json
{
  "source": "https://s3.amazonaws.com/bucket/input.pdf",
  "destination": "https://s3.amazonaws.com/bucket/output/",
  "webhook": "https://example.com/webhook",
  "unique_id": "client-123"
}
```

**Response:**
```json
{
  "message": "PDF conversion request received",
  "unique_id": "client-123",
  "status": "accepted"
}
```

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby-based AWS SAM (Serverless Application Model) application that implements a containerized Lambda function with API Gateway integration. The application uses Docker for packaging and deployment.

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
sam local invoke HelloWorldFunction --event events/event.json  # Test function with sample event
```

### Testing

```bash
ruby tests/unit/test_handler.rb  # Run unit tests
```

### Monitoring

```bash
sam logs -n HelloWorldFunction --stack-name content_processing --tail  # View Lambda logs
```

### Cleanup

```bash
sam delete --stack-name content_processing  # Delete the deployed stack
```

## Architecture

The application follows AWS SAM patterns with containerized Ruby Lambda functions:

- **template.yaml**: Defines the serverless infrastructure including Lambda function configuration, API Gateway routes, and Docker packaging settings
- **pdf_converter/app.rb**: Main Lambda handler implementing the business logic with standard Lambda event/context parameters
- **pdf_converter/Dockerfile**: Multi-stage Docker build using AWS Lambda Ruby base images
- **samconfig.toml**: SAM CLI configuration with deployment settings including parallel builds and warm container support
- **events/**: Contains sample API Gateway proxy events for local testing

The Lambda function is configured with:

- 512 MB memory
- 3-second timeout
- Container packaging using Ruby 3.4
- API endpoint at `/hello` responding to GET requests

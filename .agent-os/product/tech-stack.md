# Technical Stack

## Core Technologies

- **Application Framework:** AWS SAM (Serverless Application Model) v1.0+
- **Runtime:** Ruby 3.4
- **Container:** Docker with AWS Lambda base images

## Backend Services

- **Database System:** DynamoDB (for job tracking)
- **Object Storage:** AWS S3
- **Secrets Management:** AWS Secrets Manager
- **Authentication:** JWT with shared secrets

## Development Tools

- **Local Development:** LocalStack
- **Testing Framework:** RSpec
- **Import Strategy:** Bundler (Gemfile)

## Libraries & Dependencies

- **AWS SDK:** aws-sdk-s3, aws-sdk-secretsmanager
- **Async Processing:** Async gem
- **Image Processing:** libvips via ruby-vips
- **PDF Processing:** pdfium (for libvips PDF support)
- **HTTP Client:** Net::HTTP (Ruby standard library)

## Infrastructure

- **Application Hosting:** AWS Lambda
- **API Gateway:** AWS API Gateway v2
- **Asset Hosting:** AWS S3
- **Deployment Solution:** AWS SAM CLI
- **Monitoring:** AWS CloudWatch

## UI/Frontend

- **UI Component Library:** N/A (API-only service)
- **CSS Framework:** N/A
- **JavaScript Framework:** N/A
- **Fonts Provider:** N/A
- **Icon Library:** N/A

## Repository

- **Code Repository URL:** TBD (to be configured)
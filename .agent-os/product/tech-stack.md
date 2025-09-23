# Technical Stack

## Core Technologies

- **Application Framework:** Ruby 3.4
- **Database System:** n/a (stateless function)
- **JavaScript Framework:** n/a (backend service only)
- **Import Strategy:** n/a (Ruby gems via Bundler)
- **CSS Framework:** n/a (no UI)
- **UI Component Library:** n/a (API only)
- **Fonts Provider:** n/a
- **Icon Library:** n/a

## Infrastructure

- **Application Hosting:** AWS Lambda (Serverless)
- **Database Hosting:** n/a
- **Asset Hosting:** AWS S3 (for processed images)
- **Deployment Solution:** AWS SAM (Serverless Application Model)
- **Code Repository URL:** TBD

## Development Stack

- **Container Platform:** Docker
- **Package Manager:** Bundler
- **Testing Framework:** RSpec
- **API Gateway:** AWS API Gateway

## Processing Libraries

- **Async Processing:** Async gem (https://rubygems.org/gems/async)
- **AWS Integration:** AWS SDK for Ruby (https://github.com/aws/aws-sdk-ruby)
- **Image Processing:** libvips (https://www.libvips.org/install.html)
- **Ruby Interface:** ruby-vips gem (https://rubygems.org/gems/ruby-vips)
- **PDF Support:** pdfium (https://github.com/libvips/libvips?tab=readme-ov-file#pdfium)

## Security

- **Authentication:** JWT tokens
- **File Transfer:** Signed S3 URLs
- **API Security:** AWS API Gateway with Lambda authorizers

## Monitoring & Operations

- **Logging:** AWS CloudWatch
- **Metrics:** AWS Lambda Insights
- **Alerts:** CloudWatch Alarms
- **Tracing:** AWS X-Ray (optional)
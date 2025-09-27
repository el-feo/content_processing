# Dependency Documentation

## JWT Authentication Dependencies

### jwt (~> 2.7)

- **Purpose**: JSON Web Token implementation for Ruby
- **Version**: 2.7+ (latest stable)
- **Usage**: Token generation and validation for API authentication
- **Documentation**: <https://github.com/jwt/ruby-jwt>

### aws-sdk-secretsmanager (~> 1)

- **Purpose**: AWS SDK for Secrets Manager service
- **Version**: 1.x (latest stable in v1 series)
- **Usage**: Secure retrieval of JWT signing keys from AWS Secrets Manager
- **Documentation**: <https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/SecretsManager.html>

## Compatibility Notes

- **Ruby Version**: 3.4 (matches Lambda runtime)
- **AWS Lambda Runtime**: ruby3.4 base image
- **Dependencies are compatible with containerized Lambda deployment**

## Environment Variables

Required for production:

- `AWS_REGION`: AWS region for Secrets Manager (defaults to us-east-1)
- `JWT_SECRET_NAME`: Name of the secret in AWS Secrets Manager (defaults to pdf-converter/jwt-secret)

## Installation

```bash
bundle install
```

## Testing

Dependencies are automatically loaded when running tests:

```bash
bundle exec rspec
```

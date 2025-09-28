# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-09-27-pdf-image-conversion/spec.md

> Created: 2025-09-27
> Version: 1.0.0

## Technical Requirements

### Core Dependencies
- **libvips**: Version 8.14+ with pdfium support
- **ruby-vips**: Ruby bindings for libvips
- **pdfium**: PDF rendering backend (bundled with libvips)

### Docker Configuration
- Update Dockerfile to include libvips and pdfium dependencies
- Ensure ARM64 compatibility for AWS Lambda
- Optimize image size while including necessary libraries

### Conversion Specifications
- **Input**: PDF file (downloaded to temporary storage)
- **Output**: PNG images (one per page)
- **Default DPI**: 300 (configurable via environment variable)
- **Color Profile**: sRGB
- **Compression**: PNG optimization enabled
- **Naming Convention**: `{unique_id}_page_{page_number}.png`

### Memory Management
- Streaming conversion to minimize memory footprint
- Process pages individually to handle large documents
- Implement garbage collection between page conversions
- Maximum memory usage target: 1.5GB (within Lambda limits)

### Error Handling
- Invalid PDF format detection
- Corrupted page recovery
- Memory exhaustion protection
- Conversion timeout handling
- Detailed error logging with page-level granularity

## Approach

### Conversion Pipeline
1. **PDF Validation**: Verify PDF integrity and page count
2. **Configuration Setup**: Apply DPI and quality settings
3. **Page-by-Page Processing**: Convert each page individually
4. **Memory Management**: Clean up resources between pages
5. **Output Validation**: Verify PNG generation success
6. **Webhook Notification**: Report conversion status and results

### Integration Points
- **Lambda Handler**: Extend existing `app.rb` with conversion logic
- **File Management**: Utilize existing temporary file handling
- **Error Reporting**: Integrate with current error response format
- **Logging**: Enhance existing CloudWatch logging
- **Configuration**: Use environment variables for settings

### Performance Optimizations
- Pre-warm libvips instances where possible
- Optimize PNG compression settings for Lambda environment
- Implement intelligent DPI scaling based on PDF characteristics
- Use libvips streaming where applicable

## External Dependencies

### System Libraries
- **libvips**: Core image processing library
- **libpoppler**: PDF parsing (fallback if pdfium unavailable)
- **libpng**: PNG encoding optimization
- **zlib**: Compression support

### Ruby Gems
- **ruby-vips**: (~> 2.2) - Ruby bindings for libvips
- **mini_magick**: (removal) - Replace existing ImageMagick dependency

### Lambda Environment
- **Memory**: Increase to 2048MB for conversion processing
- **Timeout**: Maintain 60 seconds for conversion completion
- **Temporary Storage**: Utilize /tmp for intermediate files
- **Environment Variables**:
  - `CONVERSION_DPI`: Default DPI setting (default: 300)
  - `PNG_COMPRESSION`: Compression level (default: 6)
  - `MAX_PAGES`: Maximum pages to process (default: unlimited)
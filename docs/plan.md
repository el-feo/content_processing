We are creating a function as a service in the current project.
As a user I want to be able to send a message in JSON format
that includes a signed S3 URL as a source where a PDF is stored and a signed S3 URL for a destination.

Example payload:

```json
{
 source: "signedAWS_url",
 destination: "signedAWS_url",
 webhook: "webhook_url",
}
```

When the app receives the signed S3 url and a unique JWT key in the header
it will use this key to authenticate the request and download the PDF
then using [libvips via it's ruby gem](https://rubygems.org/gems/ruby-vips) will extract images for each page of the PDF.

using the provided destination the app will stream the images to the S3 location.
After all of the images have been stored in the destination folder the app
will send a success message to the webhook.

imagine there maybe additional functionality in the future, like text extraction or watermarking.

start by renaming "hellow_world" to match the intent of the application
modify the existing pdf_converter app to accomplish this.

Use context7 to look up documentation.

the tech stack:
docker
ruby
aws sdk - https://github.com/aws/aws-sdk-ruby
rspec for testing
Async for concurrency https://rubygems.org/gems/async
libvips for image processing https://www.libvips.org/install.html
ruby-vips to interface with libvips https://rubygems.org/gems/ruby-vips
pdfium so libvips can extract images - https://github.com/libvips/libvips?tab=readme-ov-file#pdfium
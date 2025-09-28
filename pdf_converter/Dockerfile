# building phase
#
FROM public.ecr.aws/sam/build-ruby3.4 as build-image

# Install build dependencies for libvips
RUN dnf update -y && \
    dnf groupinstall -y "Development Tools" && \
    dnf install -y \
    cmake \
    pkg-config \
    glib2-devel \
    expat-devel \
    libjpeg-turbo-devel \
    libpng-devel \
    libtiff-devel \
    libwebp-devel \
    libexif-devel \
    lcms2-devel \
    poppler-glib-devel \
    librsvg2-devel \
    libgsf-devel \
    fftw-devel \
    pango-devel \
    orc-devel \
    && dnf clean all

# Build and install libvips from source (with poppler for PDF support)
ENV VIPS_VERSION=8.15.0
RUN cd /tmp && \
    curl -L https://github.com/libvips/libvips/releases/download/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz -o vips.tar.xz && \
    tar xf vips.tar.xz && \
    cd vips-${VIPS_VERSION} && \
    ./configure --prefix=/usr --libdir=/usr/lib64 && \
    make -j$(nproc) && \
    make install && \
    ldconfig || true && \
    cd / && \
    rm -rf /tmp/vips*

ARG SCRATCH_DIR=/var/task/build

ENV GEM_HOME=${SCRATCH_DIR}
ENV PKG_CONFIG_PATH=/usr/lib64/pkgconfig:$PKG_CONFIG_PATH

COPY app.rb Gemfile jwt_authenticator.rb pdf_downloader.rb url_validator.rb ./
COPY lib ./lib
RUN bundle install
RUN cp -r ${GEM_HOME}/* .
RUN rm -r ${GEM_HOME}

# runtime emulation phase
#
FROM public.ecr.aws/lambda/ruby:3.4

# Install runtime dependencies
RUN dnf update -y && \
    dnf install -y \
    glib2 \
    expat \
    libjpeg-turbo \
    libpng \
    libtiff \
    libwebp \
    libexif \
    lcms2 \
    poppler-glib \
    librsvg2 \
    libgsf \
    fftw \
    pango \
    orc \
    && dnf clean all

# Copy libvips from build stage
COPY --from=build-image /usr/lib64/libvips* /usr/lib64/
COPY --from=build-image /usr/lib64/pkgconfig/vips* /usr/lib64/pkgconfig/
COPY --from=build-image /usr/include/vips /usr/include/vips
COPY --from=build-image /usr/bin/vips* /usr/bin/

# Set environment for libvips
ENV LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH
ENV VIPS_WARNING=0
ENV GEM_HOME=${LAMBDA_TASK_ROOT}

COPY --from=build-image /var/task/ ./

# Command can be overwritten by providing a different command in the template directly.
CMD ["app.lambda_handler"]
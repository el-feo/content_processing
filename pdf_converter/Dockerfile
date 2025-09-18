# building phase
#
FROM --platform=linux/amd64 public.ecr.aws/sam/build-ruby3.4 as build-image

ARG SCRATCH_DIR=/var/task/build

ENV GEM_HOME=${SCRATCH_DIR}

# Install system dependencies for libvips and pdfium
# Amazon Linux 2023 uses dnf and has different package availability
RUN dnf update -y && \
    dnf groupinstall -y "Development Tools" && \
    dnf install -y \
    gcc \
    gcc-c++ \
    make \
    pkg-config \
    glib2-devel \
    expat-devel \
    libpng-devel \
    libjpeg-turbo-devel \
    giflib-devel \
    librsvg2-devel \
    poppler-glib-devel \
    fftw3-devel \
    libexif-devel \
    libtiff-devel \
    orc-devel \
    meson \
    ninja-build \
    wget \
    cmake \
    tar \
    xz || true

# Download and install pdfium (using x64 for compatibility with --platform=linux/amd64)
RUN cd /tmp && \
    wget https://github.com/bblanchon/pdfium-binaries/releases/latest/download/pdfium-linux-x64.tgz && \
    tar -xzf pdfium-linux-x64.tgz && \
    cp -r lib/* /usr/local/lib/ && \
    cp -r include/* /usr/local/include/ && \
    echo "/usr/local/lib" >> /etc/ld.so.conf && \
    rm -rf /tmp/pdfium*

# Download and install libvips with pdfium support
RUN cd /tmp && \
    wget https://github.com/libvips/libvips/releases/download/v8.15.1/vips-8.15.1.tar.xz && \
    tar xf vips-8.15.1.tar.xz && \
    cd vips-8.15.1 && \
    meson setup build --prefix=/usr/local --buildtype=release && \
    cd build && \
    meson compile && \
    meson install && \
    rm -rf /tmp/vips*

COPY app.rb Gemfile ./
RUN bundle install
RUN cp -r ${GEM_HOME}/* .
RUN rm -r ${GEM_HOME}

# runtime emulation phase
#
FROM --platform=linux/amd64 public.ecr.aws/lambda/ruby:3.4

ENV GEM_HOME=${LAMBDA_TASK_ROOT}

# Install runtime dependencies
# Amazon Linux 2023 runtime uses dnf
RUN dnf update -y && \
    dnf install -y \
    glib2 \
    expat \
    libpng \
    libjpeg-turbo \
    giflib \
    librsvg2 \
    poppler-glib \
    fftw3 \
    libexif \
    libtiff \
    orc && \
    dnf clean all

# Copy pdfium and libvips libraries from build stage
COPY --from=build-image /usr/local/ /usr/local/

# Create symlinks for libvips library versions
RUN if [ -e /usr/local/lib/libvips.so ]; then \
        ln -sf /usr/local/lib/libvips.so /usr/local/lib/libvips.so.42 && \
        ln -sf /usr/local/lib/libvips.so /usr/local/lib/vips.so.42; \
    else \
        echo "ERROR: /usr/local/lib/libvips.so not found, cannot create symlinks." >&2; \
        exit 1; \
    fi && \
    ls -la /usr/local/lib/libvips* || echo "No libvips files found"

# Set library path for runtime
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64:${LD_LIBRARY_PATH}"
ENV VIPS_LIBRARY_PATH="/usr/local/lib"

# Copy application code
COPY --from=build-image /var/task/ ./

# Command can be overwritten by providing a different command in the template directly.
CMD ["app.lambda_handler"]

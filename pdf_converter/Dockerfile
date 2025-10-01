# building phase
#
FROM public.ecr.aws/sam/build-ruby3.4 as build-image

# Install build dependencies for libvips and pdfium
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
    fftw-devel \
    pango-devel \
    orc-devel \
    python3 \
    python3-pip \
    autoconf \
    automake \
    libtool \
    gtk-doc \
    gobject-introspection-devel \
    meson \
    ninja-build \
    && dnf clean all

# Build and install pdfium from source
ENV PDFIUM_VERSION=6721
RUN cd /tmp && \
    curl -L https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F${PDFIUM_VERSION}/pdfium-linux-x64.tgz -o pdfium.tgz && \
    tar xf pdfium.tgz && \
    mkdir -p /usr/local/include/pdfium && \
    mkdir -p /usr/local/lib && \
    mkdir -p /usr/local/lib/pkgconfig && \
    cp -r include/* /usr/local/include/pdfium/ && \
    cp lib/* /usr/local/lib/ && \
    echo "/usr/local/lib" >> /etc/ld.so.conf.d/pdfium.conf && \
    echo "prefix=/usr/local" > /usr/local/lib/pkgconfig/pdfium.pc && \
    echo "exec_prefix=\${prefix}" >> /usr/local/lib/pkgconfig/pdfium.pc && \
    echo "libdir=\${exec_prefix}/lib" >> /usr/local/lib/pkgconfig/pdfium.pc && \
    echo "includedir=\${prefix}/include/pdfium" >> /usr/local/lib/pkgconfig/pdfium.pc && \
    echo "" >> /usr/local/lib/pkgconfig/pdfium.pc && \
    echo "Name: pdfium" >> /usr/local/lib/pkgconfig/pdfium.pc && \
    echo "Description: PDFium library for PDF rendering" >> /usr/local/lib/pkgconfig/pdfium.pc && \
    echo "Version: 6721" >> /usr/local/lib/pkgconfig/pdfium.pc && \
    echo "Requires:" >> /usr/local/lib/pkgconfig/pdfium.pc && \
    echo "Libs: -L\${libdir} -lpdfium" >> /usr/local/lib/pkgconfig/pdfium.pc && \
    echo "Cflags: -I\${includedir}" >> /usr/local/lib/pkgconfig/pdfium.pc && \
    (ldconfig || true) && \
    rm -rf /tmp/pdfium*

# Build and install libvips from source (with pdfium and poppler for PDF support)
ENV VIPS_VERSION=8.15.0
RUN cd /tmp && \
    curl -L https://github.com/libvips/libvips/releases/download/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz -o vips.tar.xz && \
    tar -xJf vips.tar.xz && \
    cd vips-${VIPS_VERSION} && \
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:$PKG_CONFIG_PATH" \
    CPPFLAGS="-I/usr/local/include/pdfium" \
    LDFLAGS="-L/usr/local/lib" \
    meson setup _build --prefix=/usr --libdir=/usr/lib64 \
        -Dpdfium=auto && \
    cd _build && \
    ninja && \
    ninja install && \
    (ldconfig || true) && \
    cd / && \
    rm -rf /tmp/vips*

ARG SCRATCH_DIR=/var/task/build

ENV GEM_HOME=${SCRATCH_DIR}
ENV PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/lib64:$LD_LIBRARY_PATH

# Copy PDF converter file
COPY pdf_converter.rb ./

COPY app.rb Gemfile jwt_authenticator.rb pdf_downloader.rb url_validator.rb image_uploader.rb ./
COPY lib ./lib

# Install bundler and gems
RUN gem install bundler && bundle install
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
    fftw \
    pango \
    orc \
    && dnf clean all

# Copy pdfium and libvips from build stage
COPY --from=build-image /usr/local/lib/ /usr/local/lib/
COPY --from=build-image /usr/local/include/pdfium /usr/local/include/pdfium
COPY --from=build-image /etc/ld.so.conf.d/pdfium.conf /etc/ld.so.conf.d/
COPY --from=build-image /usr/lib64/libvips* /usr/lib64/
COPY --from=build-image /usr/lib64/pkgconfig/vips* /usr/lib64/pkgconfig/
COPY --from=build-image /usr/include/vips /usr/include/vips
COPY --from=build-image /usr/bin/vips* /usr/bin/

# Set environment for libvips and pdfium
RUN ldconfig || true
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/lib64:$LD_LIBRARY_PATH
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:$PKG_CONFIG_PATH
ENV VIPS_WARNING=0
ENV GEM_HOME=${LAMBDA_TASK_ROOT}

COPY --from=build-image /var/task/ ./

# Command can be overwritten by providing a different command in the template directly.
CMD ["app.lambda_handler"]
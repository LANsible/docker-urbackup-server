
# https://www.urbackup.org/server_source_install.html

ARG ARCHITECTURE
FROM multiarch/alpine:${ARCHITECTURE}-v3.13 as builder

ENV VERSION=2.4.13

# Add unprivileged user
# Done in the file directly so it exists when urbackup make install is chowning
RUN echo "urbackup:x:1000:1000:urbackup:/:" > /etc/passwd && \
    echo "urbackup:x:1000:urbackup" > /etc/group

RUN apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    crypto++-dev \
    crypto++-static && \
  apk add --no-cache \
    build-base \
    make \
    linux-headers \
    zlib-dev \
    zlib-static \
    zstd-dev \
    zstd-static \
    # needed as libcurl links with (output of pkg-config --libs --static libcurl)
    # -lcurl -lnghttp2 -lssl -lcrypto -lssl -lcrypto -lbrotlidec -lz
    curl-dev \
    curl-static \
    nghttp2-dev \
    nghttp2-static \
    openssl-dev \
    openssl-libs-static \
    brotli-dev \
    brotli-static

RUN wget -qO- https://hndl.urbackup.org/Server/${VERSION}/urbackup-server-${VERSION}.tar.gz | \
    tar -zxC "/tmp" --strip-components=1

WORKDIR /tmp

# symlink is needed since since pkg-config returns -lbrotlidec without the -static postfix
# ld can't find it otherwise
# embed the cryptopp and zstd for pure static
# --localstatedir=/ becomes the /urbackup state dir at runtime
# --disable-dependency-tracking speeds up the onetime build
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
    export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
    ln -sf /usr/lib/libbrotlidec-static.a /usr/lib/libbrotlidec.a && \
    ln -sf /usr/lib/libbrotlicommon-static.a /usr/lib/libbrotlicommon.a && \
    CFLAGS="-static -O3" LDFLAGS="-static -O3" CXXFLAGS="-static -O3" \
    LIBS="$(pkg-config --libs --static libbrotlidec libcurl)" \
    ./configure \
      --enable-embedded-cryptopp \
      --enable-embedded-zstd \
      --localstatedir=/ \
      --disable-dependency-tracking && \
    make install

# 'Install' upx from image since upx isn't available for aarch64 from Alpine
COPY --from=lansible/upx /usr/bin/upx /usr/bin/upx
# Minify binaries
# No upx: 18.8M
# --best: 6.6M
# --brute does not work
RUN chmod -s /usr/local/bin/urbackup_mount_helper /usr/local/bin/urbackup_snapshot_helper && \
    upx --best \
        /usr/local/bin/urbackupsrv \
        /usr/local/bin/urbackup_mount_helper \
        /usr/local/bin/urbackup_snapshot_helper && \
    chmod +s /usr/local/bin/urbackup_mount_helper /usr/local/bin/urbackup_snapshot_helper


#######################################################################################################################
# Final scratch image
#######################################################################################################################
FROM scratch

# Add description
LABEL org.label-schema.description="Static compiled urbackup in a scratch container"

ENV TMPDIR=/dev/shm

# Copy the unprivileged user/group
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Copy empty config directory
COPY --from=builder /urbackup /urbackup

# Copy binaries
COPY --from=builder \
  /usr/local/bin/ \
  /usr/local/bin/

# Copy needed data
COPY --from=builder \
    /usr/local/share/urbackup/ \
    /usr/local/share/urbackup/

WORKDIR /config
USER urbackup
ENTRYPOINT [ "/usr/local/bin/urbackupsrv", "run", "--config", "/urbackup", "--sqlite-tmpdir", "/dev/shm" ]
EXPOSE 55413
EXPOSE 55414
EXPOSE 55415
EXPOSE 35623/udp

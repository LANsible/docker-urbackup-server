ARG ARCHITECTURE
FROM multiarch/alpine:${ARCHITECTURE}-v3.13 as builder

ENV VERSION=2.4.13 \
  KRB5_VERSION=1.19 \
  CURL_VERSION=7.75.0

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
    ca-certificates \
    zlib-dev \
    zlib-static \
    zstd-dev \
    zstd-static \
    # kerberos build needs
    perl \
    bison \
    # openldap build needs
    groff \
    # from here down are curl dependencies
    openssl-dev \
    openssl-libs-static \
    libidn2-dev \
    libidn2-static

# Compile kerberos ourselves, Alpine one is not static
RUN mkdir -p /tmp/kerberos && \
  wget -qO- https://web.mit.edu/kerberos/www/dist/krb5/${KRB5_VERSION}/krb5-${KRB5_VERSION}.tar.gz | \
  tar -zxC "/tmp/kerberos" --strip-components=1

WORKDIR /tmp/kerberos/src

# -fcommon is needed since GCC 10 defaults to -fno-common and breaks kerberos
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  CFLAGS="-static -O3 -fPIC -fcommon" LDFLAGS="-static -O3" CXXFLAGS="-static -O3" \
  ./configure \
      --without-libedit --disable-shared --enable-static && \
  make && make install

# Compile kerberos ourselves, Alpine one is not static
RUN mkdir -p /tmp/openldap && \
  wget -qO- https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-2.4.57.tgz | \
  tar -zxC "/tmp/openldap" --strip-components=1

WORKDIR /tmp/openldap/

# disable berkeleyDB dependencies
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  CFLAGS="-static -O3 -fPIC -fcommon" LDFLAGS="-static -O3" CXXFLAGS="-static -O3" \
  ./configure --disable-shared --disable-bdb --disable-hdb && \
  make install

# Compile libcurl ourselves, Alpine one is missing LDAP, done in the same stage
# when building urbackup it depends again on the ldap and openssl libs, this spares
# the hassle of copying everything
# https://git.alpinelinux.org/aports/tree/main/curl/APKBUILD#n114
RUN mkdir -p /tmp/curl && \
    wget -qO- https://curl.haxx.se/download/curl-${CURL_VERSION}.tar.gz  | \
    tar -zxC "/tmp/curl" --strip-components=1

WORKDIR /tmp/curl

# Needed since curl links to -lgssapi
RUN ln -sf /usr/local/lib/libgssapi_krb5.a /usr/local/lib/libgssapi.a
# Adapted from https://git.alpinelinux.org/aports/tree/main/curl/APKBUILD#n104
# Produces minimal curl but still complying to this spec
# https://github.com/uroni/urbackup_backend/blob/dev/m4/libcurl.m4
# extra libs are from curl-config --static-libs
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  CFLAGS="-static -O3" LDFLAGS="-static -O3 $(pkg-config --libs --static krb5-gssapi)" CXXFLAGS="-static -O3" \
  ./configure \
      --with-pic \
      --with-libidn2 \
      --with-gssapi \
      --without-libssh2 \
      --without-brotli \
      --enable-optimize \
      --enable-static \
      --enable-ipv6 \
      --enable-rtsp \
      --enable-ldap \
      --disable-shared \
      --disable-gopher \
      --disable-smb \
      --disable-proxy \
      --disable-mqtt \
      --disable-tls-srp \
      --disable-unix-sockets \
      --disable-alt-svc && \
  make install

RUN mkdir -p /tmp/urbackup && \
  wget -qO- https://hndl.urbackup.org/Server/${VERSION}/urbackup-server-${VERSION}.tar.gz | \
  tar -zxC "/tmp/urbackup" --strip-components=1

WORKDIR /tmp/urbackup

# https://www.urbackup.org/server_source_install.html
# embed the cryptopp and zstd for pure static
# --localstatedir=/ becomes the /urbackup state dir at runtime
# --disable-dependency-tracking speeds up the onetime build
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  CFLAGS="-static -O3" LDFLAGS="-static -O3" CXXFLAGS="-static -O3" \
  ./configure --enable-embedded-cryptopp --enable-embedded-zstd --localstatedir=/ --disable-dependency-tracking && \
  make install

# # # # 'Install' upx from image since upx isn't available for aarch64 from Alpine
# # # COPY --from=lansible/upx /usr/bin/upx /usr/bin/upx
# # # # Minify binaries
# # # # No upx: 18.8M
# # # # --best: 6.6M
# # # # --brute does not work
# # # RUN chmod -s /usr/local/bin/urbackup_mount_helper /usr/local/bin/urbackup_snapshot_helper && \
# # #     upx --best \
# # #         /usr/local/bin/urbackupsrv \
# # #         /usr/local/bin/urbackup_mount_helper \
# # #         /usr/local/bin/urbackup_snapshot_helper && \
# # #     chmod +s /usr/local/bin/urbackup_mount_helper /usr/local/bin/urbackup_snapshot_helper


# # # #######################################################################################################################
# # # # Final scratch image
# # # #######################################################################################################################
# # # FROM scratch

# # # # Add description
# # # LABEL org.label-schema.description="Static compiled urbackup in a scratch container"

# # # ENV TMPDIR=/dev/shm

# # # # Copy the unprivileged user/group
# # # COPY --from=builder /etc/passwd /etc/passwd
# # # COPY --from=builder /etc/group /etc/group

# # # # Copy empty config directory
# # # COPY --from=builder /urbackup /urbackup

# # # # Copy binaries
# # # COPY --from=builder \
# # #   /usr/local/bin/ \
# # #   /usr/local/bin/

# # # # Copy needed data
# # # COPY --from=builder \
# # #     /usr/local/share/urbackup/ \
# # #     /usr/local/share/urbackup/

# # # WORKDIR /config
# # # USER urbackup
# # # ENTRYPOINT [ "/usr/local/bin/urbackupsrv", "run", "--sqlite-tmpdir", "/dev/shm" ]
# # # EXPOSE 55413
# # # EXPOSE 55414
# # # EXPOSE 55415
# # # EXPOSE 35623/udp

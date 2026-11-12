# syntax=docker/dockerfile:1.18@sha256:dabfc0969b935b2080555ace70ee69a5261af8a8f1b4df97b9e7fbcf6722eddf

FROM ghcr.io/joshuarli/musl-toolchain@sha256:a9802a6f0658ad344fd6b2577891194019ab86de1a4d494e32c9bbec820e863e AS build

RUN apk add --no-cache linux-headers=7.0.0-r1

WORKDIR /src

ARG GIT_VERSION
ARG GIT_ARCHIVE_URL
ARG GIT_ARCHIVE_SHA256
ARG ZLIB_VERSION
ARG ZLIB_ARCHIVE_URL
ARG ZLIB_ARCHIVE_SHA256
RUN test -n "$GIT_VERSION" && test -n "$GIT_ARCHIVE_URL" && test -n "$GIT_ARCHIVE_SHA256" \
    && test -n "$ZLIB_VERSION" && test -n "$ZLIB_ARCHIVE_URL" && test -n "$ZLIB_ARCHIVE_SHA256"

# BuildKit fetches and unpacks the pinned release archives from sources.lock.json.
# Their SHA-256 keeps the sources immutable without putting a downloader or CA
# bundle in the image.
ADD --checksum=sha256:${ZLIB_ARCHIVE_SHA256} \
    --unpack=true \
    ${ZLIB_ARCHIVE_URL} /src/
ADD --checksum=sha256:${GIT_ARCHIVE_SHA256} \
    --unpack=true \
    ${GIT_ARCHIVE_URL} /src/

# Alpine's libz.a is built by GCC; build zlib with the builder's clang instead.
WORKDIR /src/zlib-${ZLIB_VERSION}
RUN set -eux; \
    CC=clang AR=llvm-ar RANLIB=llvm-ranlib CFLAGS="-O3 -fPIC -DNDEBUG" \
        ./configure --static --prefix=/opt/zlib; \
    make -j"$(getconf _NPROCESSORS_ONLN)" install

WORKDIR /src/git-${GIT_VERSION}

# musl does not expose REG_STARTEND; use Git's compatibility regex. The
# builder's default clang config links its bundled libc.a; compile and link
# against the image's /usr/lib/libc.a instead and record the linker trace for
# the release workflow's static check.
RUN set -eux; \
    cc="clang --no-default-config -fuse-ld=lld --rtlib=compiler-rt --unwindlib=none"; \
    mkdir /trace; \
    make -j"$(getconf _NPROCESSORS_ONLN)" \
        CC="$cc" \
        AR="$AR" \
        RANLIB="$RANLIB" \
        STRIP=llvm-strip \
        CFLAGS="-O3 -flto -DNDEBUG -pipe -ffunction-sections -fdata-sections -fstack-protector-strong -I/opt/zlib/include" \
        LDFLAGS="-static-pie -flto -Wl,--gc-sections -Wl,--trace -L/opt/zlib/lib" \
        NO_CURL=YesPlease \
        NO_EXPAT=YesPlease \
        NO_GETTEXT=YesPlease \
        NO_GITWEB=YesPlease \
        NO_ICONV=YesPlease \
        NO_OPENSSL=YesPlease \
        NO_PERL=YesPlease \
        NO_PYTHON=YesPlease \
        NO_REGEX=NeedsStartEnd \
        NO_RUST=YesPlease \
        NO_TCLTK=YesPlease \
        RUNTIME_PREFIX=YesPlease \
        prefix=/usr \
        bindir=/usr/bin \
        gitexecdir=bin \
        git \
        git-upload-archive \
        git-shell \
        git-upload-pack \
        git-receive-pack \
        git-submodule \
        git-submodule--helper \
        git-sh-setup \
        git-sh-i18n \
        git-sh-i18n--envsubst \
        > /tmp/build.log 2>&1 || { tail -n 100 /tmp/build.log >&2; exit 1; }; \
    grep '^/' /tmp/build.log | LC_ALL=C sort -u > /trace/linker-trace; \
    test -s /trace/linker-trace; \
    ./git --version; \
    llvm-strip --strip-unneeded git git-shell git-sh-i18n--envsubst; \
    mkdir /out; \
    test -x git; \
    test -x git-shell; \
    test -x git-submodule; \
    test -x git-submodule--helper; \
    test -s git-sh-setup; \
    test -s git-sh-i18n; \
    test -x git-sh-i18n--envsubst; \
    cp -a git git-shell git-submodule git-sh-setup git-sh-i18n git-sh-i18n--envsubst /out/; \
    chmod 644 /out/git-sh-setup /out/git-sh-i18n; \
    for helper in git-upload-archive git-upload-pack git-receive-pack git-submodule--helper; do \
        test -x "$helper"; \
        ln -s git "/out/$helper"; \
    done; \
    for helper in git git-shell; do \
        test -z "$(ldd "$helper" 2>&1 | grep -F '=>' || true)"; \
    done

COPY scripts/qualify-binaries.sh /tmp/qualify-binaries.sh

RUN sh /tmp/qualify-binaries.sh /out \
    && rm /tmp/qualify-binaries.sh

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS runtime-test

ARG GIT_VERSION
ENV GIT_EXPECTED_VERSION=${GIT_VERSION}

COPY --from=build /out/ /usr/local/bin/
COPY --chmod=755 test/runtime.sh /usr/local/bin/git-minimal-runtime-test

RUN /usr/local/bin/git-minimal-runtime-test \
    && rm /usr/local/bin/git-minimal-runtime-test

FROM scratch AS artifacts

COPY --from=runtime-test /usr/local/bin/ /
COPY --from=build /trace/linker-trace /linker-trace

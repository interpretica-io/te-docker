# Reference image for container-isolated analysis and Test Environment runs.
#
# A midair node with `isolation=container` (always the builtin `localhost`)
# runs each analysis or test in a throwaway Docker container built from the
# workspace's image. That image only has to carry the *build environment* — the
# platform injects the visao analyzer, and the suite clones and builds TE/TS
# itself per run, so this image deliberately does NOT bake TE in (that would
# pin a version and defeat the per-run checkout).
#
# A bare `ubuntu:26.04` also works: the plugin's provisioner installs this same
# set on first use. This image just bakes it in so a run starts in seconds
# instead of waiting ~2.5 min for apt. The plugin's capability probe
# (meson/ninja/gcc/flex/bison/pkg-config/git present) then skips provisioning.
#
# KEEP THE PACKAGE LIST IN LOCKSTEP with the Debian/Ubuntu superset in
# isabelle-plugin-midair/src/provision.rs (the `APT` const). Both derive from
# the TE docs (test-environment/doc/sphinx/pages/group_te_user.rst) and the
# bublik-docker image. If one changes, change the other. The cross
# toolchains below are for the image only.
FROM ubuntu:26.04

LABEL org.opencontainers.image.title="te-docker" \
      org.opencontainers.image.description="Reference build environment for midair container-isolated analysis/test runs" \
      org.opencontainers.image.source="https://github.com/interpretica-io/te-docker"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      pkg-config \
      meson \
      ninja-build \
      bison \
      flex \
      gawk \
      file \
      wget \
      rsync \
      git \
      curl \
      jq \
      ca-certificates \
      openssh-client \
      gettext \
      inotify-tools \
      pixz \
      xz-utils \
      tar \
      xsltproc \
      libxml-parser-perl \
      libxml2-dev \
      libpopt-dev \
      libjansson-dev \
      libyaml-dev \
      libcurl4-openssl-dev \
      libglib2.0-dev \
      libssl-dev \
      libpcre2-dev \
      libbsd-dev \
      libpcap-dev \
      libtirpc-dev \
      libnl-3-dev \
      libkrb5-dev \
      libffi-dev \
 && rm -rf /var/lib/apt/lists/*

# Cross toolchains for the Test Agents of other operating systems. They are
# not a part of the provisioner set above: a run on a bare image builds only
# the agents of Linux.
#
# Windows x86-64: MinGW-w64 of the distribution.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc-mingw-w64-x86-64 \
      binutils-mingw-w64-x86-64 \
 && rm -rf /var/lib/apt/lists/*

# bsdtar unpacks the archives below: GNU tar cannot make directories under
# the amd64 emulation of Docker on Apple silicon (Rosetta), which an amd64
# build of the image on a Mac runs in.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libarchive-tools \
 && rm -rf /var/lib/apt/lists/*

# Windows ARM64: llvm-mingw. Its directory goes to the end of PATH, so its
# x86_64-w64-mingw32-* wrappers do not hide the MinGW-w64 of the distribution.
ARG LLVM_MINGW_VERSION=20261020
ARG LLVM_MINGW_SHA256_X86_64=55064b60b991a1e1e8090b8c2f84e82b22cfe5903d12c159d65064cf5e8ae335
ARG LLVM_MINGW_SHA256_AARCH64=ca16bb0f4f485876496fa46ad8d353c525eba57d0cf9e9e49ec1738fe4810151
RUN set -e; \
    case "$(uname -m)" in \
      x86_64)  arch=x86_64;  sum=${LLVM_MINGW_SHA256_X86_64} ;; \
      aarch64) arch=aarch64; sum=${LLVM_MINGW_SHA256_AARCH64} ;; \
      *) echo "llvm-mingw has no build for $(uname -m)" >&2; exit 1 ;; \
    esac; \
    name=llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-22.04-${arch}; \
    curl -fsSL -o /tmp/llvm-mingw.tar.xz \
      https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/${name}.tar.xz; \
    echo "${sum}  /tmp/llvm-mingw.tar.xz" | sha256sum -c -; \
    bsdtar -xJf /tmp/llvm-mingw.tar.xz -C /opt; \
    mv /opt/${name} /opt/llvm-mingw; \
    rm /tmp/llvm-mingw.tar.xz
ENV PATH="${PATH}:/opt/llvm-mingw/bin"

# macOS: clang and the Mach-O linker of lld. The license of Apple does not
# let the image carry the SDK, so mount one at run time:
#   docker run -v /path/to/MacOSX.sdk:/opt/macos-sdk:ro ...
# The wrappers take the SDK from MACOS_SDK and the oldest supported macOS
# from MACOS_MIN. Their names follow the --host triplets of the Builder.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bzip2 \
      clang \
      lld \
      llvm \
 && rm -rf /var/lib/apt/lists/*
# ta_job needs PCRE2. It cannot be built without the SDK, so the image
# carries the sources, and the wrappers build a static library into
# MACOS_DEPS the first time a build runs one of them.
ARG PCRE2_VERSION=10.47
ARG PCRE2_SHA256=47fe8c99461250d42f89e6e8fdaeba9da057855d06eb7fc08d9ca03fd08d7bc7
RUN set -e; \
    mkdir -p /usr/local/src/te /opt/macos-deps; \
    chmod 1777 /opt/macos-deps; \
    curl -fsSL -o /usr/local/src/te/pcre2.tar.bz2 \
      https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.bz2; \
    echo "${PCRE2_SHA256}  /usr/local/src/te/pcre2.tar.bz2" | sha256sum -c -
COPY apple-darwin-wrap /usr/local/libexec/te/apple-darwin-wrap
RUN set -e; \
    for t in aarch64-apple-darwin x86_64-apple-darwin; do \
      for tool in gcc cc cpp ld ar as nm strip ranlib pkg-config; do \
        ln -s ../libexec/te/apple-darwin-wrap /usr/local/bin/${t}-${tool}; \
      done; \
    done
ENV MACOS_SDK=/opt/macos-sdk \
    MACOS_MIN=11.0 \
    MACOS_DEPS=/opt/macos-deps

# The container is driven by `docker exec`; the platform supplies the actual
# command per run. Keeping it alive is the runtime's job (`sleep infinity`),
# so no ENTRYPOINT/CMD is set here.

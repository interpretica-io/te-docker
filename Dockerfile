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
# let the image carry the SDK of Xcode. The image makes an open SDK from the
# libc files of Zig instead: the headers of the C library of macOS and the
# symbols of libSystem, with no frameworks. The agents need no more. An SDK
# of Xcode mounted at run time takes its place:
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
ARG ZIG_VERSION=0.17.1
ARG ZIG_SHA256_X86_64=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a
ARG ZIG_SHA256_AARCH64=a1546d5646eb184437918d6635ca6b762a0e889eac09cef720ee7a1ed3fe7795
COPY macos-open-sdk /usr/local/libexec/te/macos-open-sdk
RUN set -e; \
    case "$(uname -m)" in \
      x86_64)  arch=x86_64;  sum=${ZIG_SHA256_X86_64} ;; \
      aarch64) arch=aarch64; sum=${ZIG_SHA256_AARCH64} ;; \
      *) echo "Zig has no build for $(uname -m)" >&2; exit 1 ;; \
    esac; \
    name=zig-${arch}-linux-${ZIG_VERSION}; \
    curl -fsSL -o /tmp/zig.tar.xz \
      https://ziglang.org/download/${ZIG_VERSION}/${name}.tar.xz; \
    echo "${sum}  /tmp/zig.tar.xz" | sha256sum -c -; \
    mkdir /tmp/zig; \
    bsdtar -xJf /tmp/zig.tar.xz -C /tmp/zig --strip-components=1 \
      ${name}/lib/libc/include/any-darwin-any ${name}/lib/libc/darwin; \
    /usr/local/libexec/te/macos-open-sdk /tmp/zig/lib/libc /opt/macos-sdk-open; \
    rm -rf /tmp/zig /tmp/zig.tar.xz
# Zig leaves out some headers which the agents need: of the network stack
# for TAD and of Sun RPC. They come from the open sources of Apple under
# APSL 2.0: xnu, the kernel, and Libinfo. An entry is the repository, the
# tag, the path in the repository and the SHA-256 of the file. The header
# goes to the directory of the SDK named as the directory of the path:
# bsd/netinet/ip6.h to usr/include/netinet, rpc.subproj/xdr.h to
# usr/include/rpc.
ARG XNU_TAG=xnu-12377.121.6
ARG LIBINFO_TAG=Libinfo-600
RUN set -e; \
    inc=/opt/macos-sdk-open/usr/include; \
    for f in \
      xnu/${XNU_TAG}/bsd/netinet/icmp6.h:d4cdbba557b7bc58590073f1acec57cf9ed07bfe2c94d79dd6aa30ed52581b56 \
      xnu/${XNU_TAG}/bsd/netinet/if_ether.h:84fc54c75a77512062617a3b9bc01c7584377ead4f4d4880cac4da3c00e89a3a \
      xnu/${XNU_TAG}/bsd/netinet/ip_icmp.h:c81eeb30242c814562d8d07d59f2dd249d9b7a5c59f65500563b3c86dc64a7c1 \
      xnu/${XNU_TAG}/bsd/netinet/ip6.h:86fd0f4ff3732c5050b37cafa3935ec57d8c1f8811c704173e60f3b13c2e4e07 \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/auth.h:f15db9117f43080433820e4aed3be888bab473ffd4d46f3d0b6a0a1a0b1c584c \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/auth_unix.h:c1f5ce290d14a89d47371595d305a3c5d07e53eb2cd3c77a847c0c53f7f8dfee \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/clnt.h:def33cff794665fc5d3496be954b11ebf3f13556d1c381c9b7de2d35e69e40da \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/pmap_clnt.h:19e5693bd1591e7d998f2e9053921db24782c62374a031c961e377a08716a74e \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/pmap_prot.h:096462e325ec049c0de4c5256a41605dca61d815726f2ae5fd5677081f028d2e \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/pmap_rmt.h:62b4f617b5006218a9edfb89c4d1fd61d92cb7e7a71822e9c1227dabb148b2ea \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/rpc.h:d7378bad99f70411ec2d3e8d7ccb17fa79c9bada5b95cc753184e17180ce57b5 \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/rpc_msg.h:c9597c172a6f5a5886972acc6c3c88f1d373873ab44a8f9ccae34cc9c825742c \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/svc.h:7ac97a56d282024271560ce475a83acafbba33c2961063e5133054eeeceacc48 \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/svc_auth.h:f0482e34894a663677513db797de62c275a41b2bb10f866caefad7462a6ea86b \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/types.h:25750b7608303816355cb50269fcbdb85f96a790485470f9d8b6b76ce59f8a9c \
      Libinfo/${LIBINFO_TAG}/rpc.subproj/xdr.h:e83ba123f655ceedd84179aef47d5d5457088459d3dcb3362667e43d0821ea4a; \
    do \
      path=${f%%:*}; \
      dir=$(basename "$(dirname "${path}")"); \
      case "${dir}" in rpc.subproj) dir=rpc ;; esac; \
      h=${inc}/${dir}/$(basename "${path}"); \
      mkdir -p "$(dirname "${h}")"; \
      curl -fsSL -o "${h}" \
        "https://raw.githubusercontent.com/apple-oss-distributions/${path}"; \
      echo "${f#*:}  ${h}" | sha256sum -c -; \
    done
# sys/syscall.h is made from the table of the system calls of xnu, as
# the build of xnu makes it.
RUN set -e; \
    mkdir /tmp/sysc; \
    cd /tmp/sysc; \
    for f in \
      syscalls.master:7e866891439ad5b3464777d2cacc3b82fc2e7f439fb5a8686c3e6f160d5aeab5 \
      makesyscalls.sh:bd44c344880e121277d33c7539c05915a030a52c4ceab7c9f88e54f373293c67; \
    do \
      curl -fsSL -o "${f%%:*}" \
        "https://raw.githubusercontent.com/apple-oss-distributions/xnu/${XNU_TAG}/bsd/kern/${f%%:*}"; \
      echo "${f#*:}  ${f%%:*}" | sha256sum -c -; \
    done; \
    sh makesyscalls.sh syscalls.master header >/dev/null 2>&1; \
    mv syscall.h /opt/macos-sdk-open/usr/include/sys/syscall.h; \
    cd /; \
    rm -rf /tmp/sysc
# ta_job needs PCRE2, and TAD needs libpcap, which the open SDK lacks. They
# cannot be built without an SDK, so the image carries the sources, and the
# wrappers build static libraries into MACOS_DEPS the first time a build
# runs one of them.
ARG PCRE2_VERSION=10.47
ARG PCRE2_SHA256=47fe8c99461250d42f89e6e8fdaeba9da057855d06eb7fc08d9ca03fd08d7bc7
ARG LIBPCAP_VERSION=1.10.7
ARG LIBPCAP_SHA256=68fa62cffb974f4275641ce14c2e2d75739251f30e00e6a0900903b247d76a03
RUN set -e; \
    mkdir -p /usr/local/src/te /opt/macos-deps; \
    chmod 1777 /opt/macos-deps; \
    curl -fsSL -o /usr/local/src/te/pcre2.tar.bz2 \
      https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.bz2; \
    echo "${PCRE2_SHA256}  /usr/local/src/te/pcre2.tar.bz2" | sha256sum -c -; \
    curl -fsSL -o /usr/local/src/te/libpcap.tar.xz \
      https://www.tcpdump.org/release/libpcap-${LIBPCAP_VERSION}.tar.xz; \
    echo "${LIBPCAP_SHA256}  /usr/local/src/te/libpcap.tar.xz" | sha256sum -c -
COPY apple-darwin-wrap /usr/local/libexec/te/apple-darwin-wrap
RUN set -e; \
    for t in aarch64-apple-darwin x86_64-apple-darwin; do \
      for tool in gcc cc cpp ld ar as nm strip ranlib pkg-config; do \
        ln -s ../libexec/te/apple-darwin-wrap /usr/local/bin/${t}-${tool}; \
      done; \
    done
ENV MACOS_SDK=/opt/macos-sdk \
    MACOS_OPEN_SDK=/opt/macos-sdk-open \
    MACOS_MIN=11.0 \
    MACOS_DEPS=/opt/macos-deps

# The container is driven by `docker exec`; the platform supplies the actual
# command per run. Keeping it alive is the runtime's job (`sleep infinity`),
# so no ENTRYPOINT/CMD is set here.

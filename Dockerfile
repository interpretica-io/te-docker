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
# bublik-docker image. If one changes, change the other.
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

# The container is driven by `docker exec`; the platform supplies the actual
# command per run. Keeping it alive is the runtime's job (`sleep infinity`),
# so no ENTRYPOINT/CMD is set here.

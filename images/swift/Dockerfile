# A runner image for the "swift" scale set: GitHub's runner image plus the Swift toolchain from
# swift.org, without sudo. Build it with .github/workflows/images.yml (or `docker build`).
#
# The base is the image GitHub supports for actions-runner-controller, pinned by digest. Bump the
# tag and the digest within 30 days of every actions/runner release: GitHub stops queueing jobs to
# runners that are older (README, "Operations"). The runner's Ubuntu release and the toolchain's
# must match (24.04 for both here).
FROM ghcr.io/actions/actions-runner:2.338.0@sha256:4ffadc0002b2581327e06101fc8c06cd189232baf79fe561fac9caeb76f5e807

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The system libraries Swift needs on Ubuntu 24.04, as listed by swift.org's tarball installation
# guide (https://www.swift.org/install/linux/tarball/) and swiftlang/swift-docker. Package versions
# are not pinned: the base image is, and Ubuntu's archive only carries the current versions.
# hadolint ignore=DL3008
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libncurses-dev \
      libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata \
      unzip zip zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

# The release tarball, checked against its SHA-256. To move to a new version: download the
# tarball and its .sig from swift.org, verify the signature with the release key
# (https://www.swift.org/keys/all-keys.asc), then put its sha256sum here.
ARG SWIFT_VERSION=6.4.0
ARG SWIFT_SHA256=69f7b2b4dbce6090b6c92194b71149a057e16269093b5a9dded38afc4a05094e
RUN curl -fsSL -o /tmp/swift.tar.gz \
      "https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz" \
 && echo "${SWIFT_SHA256}  /tmp/swift.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/swift.tar.gz -C / --strip-components=1 \
 && chmod -R o+r /usr/lib/swift \
 && rm /tmp/swift.tar.gz \
 && swift --version

# The base image gives the runner user passwordless sudo. A job must not become root: remove the
# user from the sudo group and remove sudo itself. (The pod template's allowPrivilegeEscalation:
# false would also stop a setuid binary; this removes the binary.)
RUN gpasswd -d runner sudo \
 && apt-get purge -y sudo \
 && rm -rf /var/lib/apt/lists/*

# Numeric, so Kubernetes can check runAsNonRoot. uid 1001 is the base image's runner user.
USER 1001
WORKDIR /home/runner

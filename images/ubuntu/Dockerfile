# A generic runner image for the "ubuntu" scale set: GitHub's runner image plus common build
# tools, without sudo. A job cannot install packages at run time; add what your jobs need here.
#
# Bump the base tag and digest within 30 days of every actions/runner release (README,
# "Operations").
FROM ghcr.io/actions/actions-runner:2.338.0@sha256:4ffadc0002b2581327e06101fc8c06cd189232baf79fe561fac9caeb76f5e807

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Package versions are not pinned: the base image is, and Ubuntu's archive only carries the
# current versions.
# hadolint ignore=DL3008
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential ca-certificates file gnupg2 jq make openssh-client pkg-config \
      python3 python3-pip python3-venv rsync tzdata unzip wget xz-utils zip zstd \
 && rm -rf /var/lib/apt/lists/*

# No sudo for the runner user (see images/swift/Dockerfile).
RUN gpasswd -d runner sudo \
 && SUDO_FORCE_REMOVE=yes apt-get purge -y sudo \
 && rm -rf /var/lib/apt/lists/*

# The same Node as the Swift image and AIDepartment's ci/tools.pin, independent of the runner's
# internal Node. Keep this first on PATH for jobs in the ci-light set.
ARG NODE_VERSION=24.22.0
ARG NODE_SHA256=cc2f601cee82d9a5a233302fe307abc600727035fd7d2c3a3571755989e95008
RUN curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
 && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/node \
 && tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 --no-same-owner \
 && rm /tmp/node.tar.xz
ENV PATH="/opt/node/bin:${PATH}"

USER 1001
WORKDIR /home/runner

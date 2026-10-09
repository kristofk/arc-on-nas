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
 && apt-get purge -y sudo \
 && rm -rf /var/lib/apt/lists/*

USER 1001
WORKDIR /home/runner

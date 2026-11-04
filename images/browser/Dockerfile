# The "browser" image: the generic ubuntu image (images/ubuntu/Dockerfile, repeated here step for
# step) plus the shared libraries and fonts headless Chrome for Testing needs. Chrome itself is not
# installed: each job installs the version it pins (for example with @puppeteer/browsers), so a
# browser update needs no image rebuild. A job cannot install packages at run time.
#
# The base tag, digest and Node are the same as in images/ubuntu/Dockerfile, and every package
# installed there is installed here (scripts/check-consistency.sh). Bump both files together.
FROM ghcr.io/actions/actions-runner:2.338.0@sha256:4ffadc0002b2581327e06101fc8c06cd189232baf79fe561fac9caeb76f5e807

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The ubuntu image's packages. Versions are not pinned: the base image is, and Ubuntu's archive only
# carries the current versions.
# hadolint ignore=DL3008
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential ca-certificates file gnupg2 jq make openssh-client pkg-config \
      python3 python3-pip python3-venv rsync tzdata unzip wget xz-utils zip zstd \
 && rm -rf /var/lib/apt/lists/*

# Chrome for Testing's runtime dependencies: the list in its own chrome-linux64/deb.deps, under
# Ubuntu 24.04's names (the t64 packages), without what headless Chrome does not use: GTK (only
# loaded for a window), libvulkan1 (Chrome bundles libvulkan.so.1 and SwiftShader), libcurl,
# wget (above) and xdg-utils. fonts-liberation is the fallback for pages without web fonts.
# scripts/check-image-runtime.sh starts a pinned Chrome for Testing build with them.
# hadolint ignore=DL3008
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      fonts-liberation libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 \
      libcairo2 libcups2t64 libdbus-1-3 libexpat1 libgbm1 libglib2.0-0t64 libnspr4 libnss3 \
      libpango-1.0-0 libudev1 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 \
      libxkbcommon0 libxrandr2 \
 && rm -rf /var/lib/apt/lists/*

# No sudo for the runner user (see images/swift/Dockerfile).
RUN gpasswd -d runner sudo \
 && SUDO_FORCE_REMOVE=yes apt-get purge -y sudo \
 && rm -rf /var/lib/apt/lists/*

# The same Node as the ubuntu image. Keep this first on PATH.
ARG NODE_VERSION=24.22.0
ARG NODE_SHA256=cc2f601cee82d9a5a233302fe307abc600727035fd7d2c3a3571755989e95008
RUN curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
 && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/node \
 && tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 --no-same-owner \
 && rm /tmp/node.tar.xz
ENV PATH="/opt/node/bin:${PATH}"

# The Chrome for Testing build scripts/check-image-runtime.sh downloads and starts to test this
# image; it is not installed. Its SHA-256 is of chrome-linux64.zip from
# https://storage.googleapis.com/chrome-for-testing-public/<version>/linux64/ (Google publishes
# none). Move it forward with the consumers' pinned versions.
ARG CHROME_VERSION=157.0.8103.38
ARG CHROME_SHA256=8cdeb344e9b2cefe59f4aea8d1d93d5d93054c03cde217665c16fc1f62e72a66

USER 1001
WORKDIR /home/runner

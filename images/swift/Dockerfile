# The swift and swift-image sets share this image. Take GitHub's runner and hooks from its
# supported image, but run swift.org's Ubuntu 26.04 toolchain on the matching distribution.
# Bump this runner tag AND digest within 30 days of each actions/runner release (README,
# "Operations"). The upstream image itself is Ubuntu 24.04; do not use it as the final base.
FROM ghcr.io/actions/actions-runner:2.338.0@sha256:4ffadc0002b2581327e06101fc8c06cd189232baf79fe561fac9caeb76f5e807 AS runner
FROM docker.io/library/ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1 \
    ImageOS=ubuntu26

# Swift's 26.04 packages: https://www.swift.org/install/linux/tarball/ (GCC 15).
# libicu-dev, libkrb5-3, libssl3t64 and zlib1g supply the self-contained .NET runner's native
# dependencies. No sudo is installed; jobs remain uid 1001 without privilege escalation.
# Package versions follow Ubuntu's archive; both source images are pinned by digest.
# hadolint ignore=DL3008
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      binutils binutils-gold ca-certificates curl git gnupg2 jq libc6-dev libcurl4-openssl-dev \
      libedit2 libgcc-15-dev libicu-dev libkrb5-3 libncurses-dev libpython3-dev libsqlite3-0 \
      libssl3t64 libstdc++-15-dev libxml2-dev libz3-dev pkg-config python3 tzdata unzip \
      xz-utils zip zlib1g-dev \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 1001 runner \
 && useradd --uid 1001 --gid runner --create-home --shell /bin/bash runner \
 && groupadd --gid 123 docker \
 && usermod -aG docker runner

COPY --from=runner --chown=1001:123 /home/runner/ /home/runner/
COPY --from=runner /usr/bin/docker /usr/bin/docker
COPY --from=runner /usr/local/lib/docker/cli-plugins/ /usr/local/lib/docker/cli-plugins/

# Public Swift 6.x release key, from https://www.swift.org/keys/all-keys.asc; its full
# fingerprint is checked below. Keep the key's renewed self-signatures when refreshing it.
COPY swift-release-key.asc /tmp/swift-release-key.asc
ARG SWIFT_VERSION=6.4.0
ARG SWIFT_SHA256=c966d52a195724238fcc082afefac8f274dff1f30cf2ace5f93ec684c17b0026
ARG SWIFT_SIGNING_KEY=52BB7E3DE28A71BE22EC05FFEF80A866B47A981F
RUN url="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2604/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu26.04.tar.gz" \
 && curl -fsSL -o /tmp/swift.tar.gz "$url" -o /tmp/swift.tar.gz.sig "$url.sig" \
 && echo "${SWIFT_SHA256}  /tmp/swift.tar.gz" | sha256sum -c - \
 && GNUPGHOME="$(mktemp -d)" \
 && export GNUPGHOME \
 && gpg --batch --quiet --import /tmp/swift-release-key.asc \
 && gpg --batch --status-file /tmp/gpg-status --verify /tmp/swift.tar.gz.sig /tmp/swift.tar.gz \
 && grep -q "^\[GNUPG:\] VALIDSIG ${SWIFT_SIGNING_KEY} " /tmp/gpg-status \
 && tar -xzf /tmp/swift.tar.gz -C / --strip-components=1 --no-same-owner \
 && chmod -R o+r /usr/lib/swift \
 && rm -rf "$GNUPGHOME" /tmp/swift.tar.gz /tmp/swift.tar.gz.sig /tmp/swift-release-key.asc /tmp/gpg-status

# AIDepartment main's ci/tools.pin (#579). Check every download before unpacking it.
ARG NODE_VERSION=24.22.0
ARG NODE_SHA256=cc2f601cee82d9a5a233302fe307abc600727035fd7d2c3a3571755989e95008
RUN curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
 && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/node \
 && tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 --no-same-owner \
 && rm /tmp/node.tar.xz
ENV PATH="/opt/node/bin:${PATH}"

ARG CADDY_VERSION=2.11.7
ARG CADDY_SHA256=727b91701a392de6ebc5027509f548bf39979e5216340d0faed8fa5e69c84f8b
RUN curl -fsSL -o /tmp/caddy.tar.gz \
      "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" \
 && echo "${CADDY_SHA256}  /tmp/caddy.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin caddy --no-same-owner \
 && rm /tmp/caddy.tar.gz

ARG BUILDCTL_VERSION=0.34.0
ARG BUILDCTL_SHA256=14813b1fb2a40082114e6d386c6fc5e7dd5298176ce7ee1a18bc33e73e109ac3
RUN curl -fsSL -o /tmp/buildkit.tar.gz \
      "https://github.com/moby/buildkit/releases/download/v${BUILDCTL_VERSION}/buildkit-v${BUILDCTL_VERSION}.linux-amd64.tar.gz" \
 && echo "${BUILDCTL_SHA256}  /tmp/buildkit.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/buildkit.tar.gz -C /usr/local/bin --strip-components=1 --no-same-owner bin/buildctl \
 && rm /tmp/buildkit.tar.gz

ARG KUBECTL_VERSION=1.36.5
ARG KUBECTL_SHA256=33bc88a24c3b09cf55bfd59e6ca977881b61fc3f25ab65bc80c65b430248648e
RUN curl -fsSL -o /tmp/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && echo "${KUBECTL_SHA256}  /tmp/kubectl" | sha256sum -c - \
 && install -m 0755 /tmp/kubectl /usr/local/bin/kubectl \
 && rm /tmp/kubectl

# Numeric so Kubernetes can check runAsNonRoot. The runtime checks in images.yml run as this user.
USER 1001
WORKDIR /home/runner

# Changelog

All notable changes to this repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Swift runners use Ubuntu 26.04 and swift.org's matching Swift 6.4.0 build, verified by its
  release signature and pinned SHA-256, while retaining GitHub's runner and container hooks.
- Both runner images bundle Node 24.22.0; the shared Swift/image runner also carries Caddy
  2.11.7, Python 3.10 or newer, curl, jq, buildctl 0.34.0 and kubectl 1.36.5 (#2).
- Image CI builds pull requests without publishing, checks the runner and tools as uid 1001,
  compiles, links, runs and tests a Foundation package, checks the runner's TLS/globalization
  with an expected GitHub authentication rejection, and publishes only from main or v* tags
  with Node (and Swift's Ubuntu release) in their tags. Existing Helm image digests stay pinned
  until an operator updates them.
- The Swift image omits the upstream image's lsb-release, software-properties-common and Docker
  daemon/containerd binaries; the Docker client, buildx, Git, curl, jq and container hooks remain.

## [0.1.0] - 2026-10-09

First release.

### Added

- A Compose stack: k3s `v1.36.5+k3s1` as a single privileged node on an internal Docker network,
  a Squid egress proxy that refuses private destinations and rotates its access log, and an
  on-demand Helm `3.22.0` client.
- Manifests: the `arc-systems` and `arc-runners` namespaces with Pod Security labels, NetworkPolicies
  (runner pods reach only DNS and the proxy; nothing reaches the controller), and a static
  PersistentVolume and claim for the warm build cache.
- Helm values for Actions Runner Controller `0.15.0`: the controller and two scale sets, `swift`
  (`minRunners: 1`) and `ubuntu` (`minRunners: 0`), with restricted pod templates, requests equal
  to limits, the proxy and the cache.
- Runner images on `ghcr.io/actions/actions-runner:2.338.0` without sudo: `swift` (Swift `6.4.0`)
  and `ubuntu` (common build tools), and a workflow that builds and pushes them.
- Scripts: `preflight.sh` (which also prints the `.env` sizing for a budget), `trial.sh`,
  `register.sh`, `warm.sh`, `prune-cache.sh`, and for development `lint.sh` and
  `check-consistency.sh`.
- An example consumer workflow with routing to GitHub-hosted runners as a fallback.
- CI: static checks and a smoke test of the stack on a GitHub-hosted runner.

[Unreleased]: https://github.com/kristofk/arc-on-nas/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kristofk/arc-on-nas/releases/tag/v0.1.0

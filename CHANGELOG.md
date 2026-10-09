# Changelog

All notable changes to this repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

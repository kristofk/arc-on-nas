# Changelog

All notable changes to this repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- The build farm left this repository for its owner's (AIDepartment, `deploy/build-farm/`): the
  `build-farm` tenant, its server, its cache volume and claim, `scripts/farm-tls.sh`, the runners'
  `allow-build-farm` policy and the farm's smoke tests. Its forwarder, `farm-forward.yml`, went to
  the owner's host setup, whose networks and addresses it names. What stays is the generic
  mechanism: `manifests/tenants/base`, `admission.yaml`, and README "Tenant namespaces", which now
  says how a tenant is added here or kept in another repository with this one's base by its
  commit, and how a host's forwarder reaches a tenant's service.

### Added

- `manifests/tenants/example/`, a tenant to copy (not applied by `kubectl apply -k
  manifests/tenants`): its namespace, quota and a cache volume reserved for its claim. The smoke
  test applies it as the second tenant beside `zuul-trial`: the Role's permissions, the volume
  bound to its claim only, and the NetworkPolicies between the two.

- The build farm's network and TLS (README "The build farm's network"): the frontend speaks TLS
  only, with a key pair from a CA of the farm's own that it reads again every minute, so a renewal
  needs no restart (`scripts/farm-tls.sh` makes the CA and signs the key pair into the Secret
  `frontend-tls`); the runner pods reach its port through the cluster's DNS (`allow-build-farm`),
  and `farm-forward.yml` forwards it to another Docker network through the NodePort
  `frontend-external`, which `build-farm`'s quota now allows; the frontend's NetworkPolicy admits
  those two and nothing else. The frontend takes no action result or file system access profile
  from a client. The smoke test checks each route, each refusal and a renewal.
- Tenant namespaces (`manifests/tenants/`, README "Tenant namespaces"): `zuul-trial` and
  `build-farm`, for users other than the cluster admin, each with Pod Security `baseline` enforced
  and `restricted` warned and audited, a ResourceQuota (CPU, memory, storage and a count of every
  kind a tenant may create) and LimitRange, a Role limited to namespaced workload, configuration
  and Service resources bound to two users, and NetworkPolicies that admit only the namespace's
  own pods and keep egress off the host and the node. Admission policies close what `baseline`
  leaves open: every container drops `NET_RAW` (added when missing), only `restricted`'s volume
  types without `csi`, images only from internet registries (also on updates), no Service
  `externalIPs`. `scripts/tenant-cert.sh` signs a user's certificate request after checking its
  subject, attributes and the stored copy, for 90 days, and writes a kubeconfig without a key;
  `api-forward.yml` forwards the API server's port 6443, and nothing else, to another Docker
  network. The smoke test checks all of it.
- The build farm's cache: a hostPath PersistentVolume `build-farm-cache`, reserved for the claim
  `cache` in `build-farm`, and Buildbarn's storage settings for it
  (`manifests/tenants/build-farm/server/config/cache.libsonnet`):
  fixed-size files of 131.2 GiB in all, below the volume's 150 GiB, with Buildbarn's recommended
  block counts for eviction. README "Tenant namespaces" has the host's part (a filesystem with a
  quota, the bind mount in `docker-compose.override.yml`). `scripts/lint.sh` evaluates the
  settings and `scripts/check-consistency.sh` checks they fit the volume; the smoke test checks
  the claim binds and another namespace's claim does not.
- The build farm's server, Buildbarn, for the tenant `build-farm` to apply
  (`manifests/tenants/build-farm/server/`, README "Tenant namespaces"): the storage pod on the
  claim `cache`, the scheduler, and the frontend that clients use, at the versions bb-deployments
  pins (bb-storage `20261102T091443Z-ca3d8b4`, bb-scheduler `20261102T094740Z-c9ba98c`), sized to
  448Mi of requests and 1.75 GiB of limits, as uid 65532 and Pod Security `restricted`. The
  configuration is jsonnet, generated into a ConfigMap; the cache settings moved next to it, from
  `build-farm/`. README has the upgrade and rollback procedure. `scripts/lint.sh` renders it with
  kustomize (added to `mise.toml`) and checks it with kubeconform, and
  `scripts/check-consistency.sh` checks the storage pod's claim, mount, directories and user
  against the cache settings. The smoke test applies it as a tenant, writes and reads a blob and an
  action result through the frontend, and reads them again after a restart of the storage pod.
- The node starts without its copy of `/dev/zfs` (`docker-compose.yml`'s and `scripts/trial.sh`'s
  entrypoint), so the kubelet can measure ZFS datasets: its cAdvisor asked the `zfs` command for a
  dataset's size whenever `/dev/zfs` existed, the k3s image has none, and with local storage
  isolation on the kubelet never started ("failed to get rootfs info: cannot find filesystem info
  for device"). Without it, cAdvisor uses `statfs`. A new CI job, "The node on ZFS", runs the node
  with its kubelet and containerd directories on ZFS datasets, isolation on, and checks that both
  are measured at their quotas and that a tenant's pod writing past its limit is evicted.
  `scripts/check-consistency.sh` checks both entrypoints.
- A disk bound for each tenant namespace: `requests.ephemeral-storage` and
  `limits.ephemeral-storage` in its ResourceQuota (`zuul-trial` 4Gi, `build-farm` 8Gi), and an
  ephemeral-storage default (512Mi, 64Mi requested) and maximum per container in its LimitRange,
  so the kubelet evicts a tenant's pod that writes past its limit and the tenants together keep to
  a known share of the filesystem under `/var/lib/kubelet`, which the runners' work folders share.
  It needs the kubelet's local storage isolation: with
  `--kubelet-arg=local-storage-capacity-isolation=false` tenant pods cannot be scheduled (README,
  "Tenant namespaces", "Disk"). The smoke test checks the defaults, the refusals and an eviction.
- A browser runner image, `arc-runner-browser`, and its example scale set `helm/browser.yaml`: the
  Ubuntu image plus the shared libraries and fonts headless Chrome for Testing needs, so jobs can
  run page tests without installing packages. Image CI downloads a pinned Chrome for Testing build,
  checks its libraries with `ldd` and starts it headless as uid 1001, drawing with WebGL
  (SwiftShader) and Canvas 2D. `helm/browser.yaml` pins the build of Images run 41937445042 on
  main by digest.

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

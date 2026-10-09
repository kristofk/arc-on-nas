#!/usr/bin/env bash
# check-consistency.sh: values that must agree across files, checked in one place.
#
# Some values cannot be shared through a variable: the proxy's fixed address is needed by
# Docker, Squid, a NetworkPolicy and the Helm values; the chart and image versions are repeated in
# documentation and scripts. This fails if any copy differs from the source of truth named below.
# CI runs it (scripts/lint.sh); run it after changing any of them.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
status=0
problem() { echo "MISMATCH: $1"; status=1; }

# Source of truth: docker-compose.yml.
proxy=$(sed -n '/^  proxy:/,/^  [a-z]/{s/^ *ipv4_address: *\([0-9.]*\).*/\1/p}' docker-compose.yml)
subnet=$(sed -n 's/^ *- subnet: *\([0-9./]*\).*/\1/p' docker-compose.yml)
k3s_image=$(sed -n 's/^ *image: *\(rancher\/k3s:[^ ]*\).*/\1/p' docker-compose.yml)
[ -n "$proxy" ] && [ -n "$subnet" ] && [ -n "$k3s_image" ] || { echo "cannot read docker-compose.yml"; exit 1; }
echo "proxy $proxy, subnet $subnet, k3s $k3s_image"

grep -q "HTTPS_PROXY: http://$proxy:3128" docker-compose.yml || problem "docker-compose.yml: an HTTPS_PROXY is not http://$proxy:3128"
if grep -nE 'HTTPS?_PROXY: ' docker-compose.yml | grep -v "http://$proxy:3128"; then problem "docker-compose.yml: proxy URL above differs"; fi
grep -q "cidr: $proxy/32" manifests/networkpolicy-runners.yaml || problem "manifests/networkpolicy-runners.yaml: ipBlock is not $proxy/32"
grep -q "acl runners src $subnet " squid.conf || problem "squid.conf: 'acl runners src' does not include $subnet"
for f in helm/swift.yaml helm/ubuntu.yaml; do
  n=$(grep -c "url: http://$proxy:3128" "$f" || true)
  [ "$n" -eq 2 ] || problem "$f: expected the http and https proxy URLs to be http://$proxy:3128"
done
node=$(sed -n '/^  k3s:/,/^  [a-z]/{s/^ *ipv4_address: *\([0-9.]*\).*/\1/p}' docker-compose.yml)
grep -q -- "--node-ip=$node$" docker-compose.yml || problem "docker-compose.yml: --node-ip is not the k3s service's ipv4_address $node"
grep -q "^subnet=$subnet$" scripts/preflight.sh || problem "scripts/preflight.sh: subnet is not $subnet"
grep -q "NO_PROXY: .*,$subnet," docker-compose.yml || problem "docker-compose.yml: NO_PROXY does not include $subnet"
gateway=$(sed -n 's/^ *gateway: *\([0-9.]*\).*/\1/p' docker-compose.yml)
grep -q "PROXY: http://$proxy:3128$" .github/workflows/ci.yml || problem ".github/workflows/ci.yml: PROXY is not http://$proxy:3128"
grep -q "GATEWAY: $gateway$" .github/workflows/ci.yml || problem ".github/workflows/ci.yml: GATEWAY is not $gateway"

# The cache: the compose mount target, the PersistentVolume's path, the claim the values mount.
# shellcheck disable=SC2016 # a literal ${CACHE_DIR...} in the compose file
mount=$(sed -n 's/^ *- \${CACHE_DIR[^}]*}:\(\/[^ ]*\).*/\1/p' docker-compose.yml)
grep -q "path: $mount/" manifests/cache.yaml || problem "manifests/cache.yaml: hostPath is not under the compose mount $mount"
claim=$(awk '/^kind: PersistentVolumeClaim/ {f=1} f && /^  name:/ {print $2; exit}' manifests/cache.yaml)
for f in helm/swift.yaml helm/ubuntu.yaml; do
  grep -q "claimName: $claim$" "$f" || problem "$f: claimName is not $claim"
  grep -q "mountPath: /home/runner/cache$" "$f" || problem "$f: the cache is not mounted at /home/runner/cache"
  grep -q "runAsUser: 1001$" "$f" || problem "$f: runAsUser is not 1001"
  grep -q "name: arc-gha-rs-controller$" "$f" || problem "$f: controllerServiceAccount is not arc-gha-rs-controller (release arc)"
done
for f in images/swift/Dockerfile images/ubuntu/Dockerfile; do
  grep -q "^USER 1001$" "$f" || problem "$f: USER is not 1001"
done

grep -q "^image=$k3s_image$" scripts/trial.sh || problem "scripts/trial.sh: image differs from docker-compose.yml"

# The chart version: helm/controller.yaml's install command is the source of truth.
chart=$(sed -n 's/.*--version \([0-9][0-9.]*\) --namespace arc-systems.*/\1/p' helm/controller.yaml | head -n 1)
[ -n "$chart" ] || { echo "cannot read the chart version from helm/controller.yaml"; exit 1; }
echo "chart $chart"
if grep -rnoE -- '--version [0-9]+\.[0-9]+\.[0-9]+|gha-runner-scale-set-[0-9]+\.[0-9]+\.[0-9]+|CHART_VERSION: "?[0-9.]+|chart_version=[0-9.]+' \
     helm README.md .github/workflows scripts \
     | grep -vE -- "(--version |gha-runner-scale-set-|CHART_VERSION: \"?|chart_version=)$chart\"?$"; then
  problem "chart versions above differ from $chart"
fi

# The runner base image: the same tag and digest in every Dockerfile, and the tags in helm/.
base=$(sed -n 's/^FROM \(ghcr.io\/actions\/actions-runner:[^ ]*\).*/\1/p' images/swift/Dockerfile)
grep -q "^FROM $base$" images/ubuntu/Dockerfile || problem "images/ubuntu/Dockerfile: base differs from images/swift/Dockerfile"
runner=${base#*:}
runner=${runner%%@*}
swift=$(sed -n 's/^ARG SWIFT_VERSION=//p' images/swift/Dockerfile)
echo "runner $runner, swift $swift"
# Any owner, and the digest you pin after building (README, "Quick start" step 8) or none yet;
# optionally quoted, optionally followed by a comment.
image_re() { echo "^ *image: \"?ghcr\.io/[^/ \"]+/arc-runner-$1:${2//./\\.}(@sha256:[0-9a-f]{64})?\"?( +#.*)?$"; }
grep -qE "$(image_re swift "$swift-$runner")" helm/swift.yaml || problem "helm/swift.yaml: image tag is not $swift-$runner"
grep -qE "$(image_re ubuntu "$runner")" helm/ubuntu.yaml || problem "helm/ubuntu.yaml: image tag is not $runner"

# Helper images used by more than one script.
alpine_pre=$(sed -n 's/^test_image=//p' scripts/preflight.sh)
alpine_trial=$(sed -n 's/^pod_image=//p' scripts/trial.sh)
[ "$alpine_pre" = "$alpine_trial" ] || problem "scripts/preflight.sh and scripts/trial.sh use different alpine images"

[ "$status" -eq 0 ] && echo "All consistent."
exit "$status"

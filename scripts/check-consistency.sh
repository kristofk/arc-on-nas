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
grep -q "image: ghcr.io/OWNER/arc-runner-swift:$swift-$runner" helm/swift.yaml || problem "helm/swift.yaml: image tag is not $swift-$runner"
grep -q "image: ghcr.io/OWNER/arc-runner-ubuntu:$runner" helm/ubuntu.yaml || problem "helm/ubuntu.yaml: image tag is not $runner"

# Helper images used by more than one script.
alpine_pre=$(sed -n 's/^test_image=//p' scripts/preflight.sh)
alpine_trial=$(sed -n 's/^pod_image=//p' scripts/trial.sh)
[ "$alpine_pre" = "$alpine_trial" ] || problem "scripts/preflight.sh and scripts/trial.sh use different alpine images"

[ "$status" -eq 0 ] && echo "All consistent."
exit "$status"

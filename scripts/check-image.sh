#!/usr/bin/env bash
# Run only on a build host, after building: scripts/check-image.sh swift|ubuntu IMAGE:TAG.
# Expected versions come from the Dockerfile; this tests the final image as the job's uid,
# with no capabilities or privilege escalation. images.yml records the output in its summary.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
set_name=${1:?usage: check-image.sh swift|ubuntu IMAGE:TAG}
ref=${2:?usage: check-image.sh swift|ubuntu IMAGE:TAG}
case "$set_name" in swift|ubuntu) ;; *) echo "unknown image set: $set_name" >&2; exit 1 ;; esac
file="images/$set_name/Dockerfile"
runner=$(sed -n 's|^FROM ghcr.io/actions/actions-runner:\([0-9.]*\)@.*|\1|p' "$file")
args=(--env "EXPECTED_RUNNER=$runner" --env "IMAGE_SET=$set_name")
for tool in NODE SWIFT CADDY BUILDCTL KUBECTL; do
  version=$(sed -n "s/^ARG ${tool}_VERSION=//p" "$file")
  if [ -n "$version" ]; then args+=(--env "EXPECTED_$tool=$version"); fi
done
docker run --rm -i --user 1001:1001 --cap-drop ALL --security-opt no-new-privileges \
  "${args[@]}" "$ref" /bin/bash -euo pipefail -s < scripts/check-image-runtime.sh

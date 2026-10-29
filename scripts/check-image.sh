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
  "${args[@]}" "$ref" /bin/bash -euo pipefail -s <<'CHECK'
test "$(id -u)" = 1001
test "$(id -g)" = 1001
test "$(id -un)" = runner
! command -v sudo
# shellcheck disable=SC1091
. /etc/os-release
if [ "$IMAGE_SET" = swift ]; then test "$VERSION_ID" = 26.04; else test "$VERSION_ID" = 24.04; fi
printf 'OS: %s; uid: %s\n' "$PRETTY_NAME" "$(id -u)"
test "$RUNNER_MANUALLY_TRAP_SIG" = 1
test "$ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT" = 1
test -x /home/runner/run.sh
test -d /home/runner/k8s
test -d /home/runner/k8s-novolume
# This starts the self-contained .NET runtime on the final distribution, without credentials.
runner=$(/home/runner/bin/Runner.Listener --version)
printf 'Runner.Listener: %s\n' "$runner"
test "$runner" = "$EXPECTED_RUNNER"
/home/runner/config.sh --help
/home/runner/externals/node24/bin/node --version
docker --version
docker buildx version
node --version
test "$(node --version)" = "v$EXPECTED_NODE"
npm --version
python3 --version
python3 -c 'import sys; assert sys.version_info >= (3, 10)'
curl --version
jq --version
if [ "$IMAGE_SET" = swift ]; then
  test "$ImageOS" = ubuntu26
  swift --version
  version=${EXPECTED_SWIFT%.0}
  test "$(swift --version | head -n 1)" = "Swift version $version (swift-$version-RELEASE)"
  swift -e 'print("Swift execution on Ubuntu 26.04: OK")'
  caddy version
  test "$(caddy version | cut -d ' ' -f 1)" = "v$EXPECTED_CADDY"
  buildctl --version
  [[ $(buildctl --version) == *" v$EXPECTED_BUILDCTL "* ]]
  kubectl version --client
  test "$(kubectl version --client -o json | jq -r .clientVersion.gitVersion)" = "v$EXPECTED_KUBECTL"
fi
CHECK

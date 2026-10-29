#!/usr/bin/env bash
# Inside the built image only, via check-image.sh. Expected versions and IMAGE_SET are passed
# by the caller. This file stays separate so scripts/lint.sh checks the container script too.
set -euo pipefail
trap 'echo "Runtime check failed at line $LINENO: $BASH_COMMAND" >&2' ERR
test "$(id -u)" = 1001
test "$(id -g)" = 1001
test "$(id -un)" = runner
if command -v sudo; then echo "sudo must not be installed" >&2; exit 1; fi
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
# The image intentionally streams runner diagnostics to stdout alongside its version line.
grep -qxF "$EXPECTED_RUNNER" <<< "$runner"
/home/runner/config.sh --help
# Force culture-aware .NET startup and a real HTTPS request. An invalid literal token must
# reach GitHub and fail authentication: a version/help-only check would not exercise TLS.
auth_log=$(mktemp /tmp/arc-runner-auth.XXXXXX)
auth_status=0
timeout 90 env LANG=en_US.UTF-8 DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=0 \
  /home/runner/config.sh --unattended --url https://github.com/actions/runner \
  --token invalid --name image-runtime-check > "$auth_log" 2>&1 || auth_status=$?
cat "$auth_log"
test "$auth_status" -ne 0
test "$auth_status" -ne 124
grep -qE "Http response code: (Unauthorized|NotFound) from 'POST https://api.github.com/actions/runner-registration'" "$auth_log"
grep -q 'Culture: en-US' "$auth_log"
test ! -e /home/runner/.runner
rm "$auth_log"
echo 'Runner TLS/ICU: GitHub authentication rejection as expected (en-US)'
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
  test "${ImageOS:?}" = ubuntu26
  swift --version
  version=${EXPECTED_SWIFT%.0}
  test "$(swift --version | head -n 1)" = "Swift version $version (swift-$version-RELEASE)"
  # Build, link, execute and test Foundation against this distribution's development libraries.
  # No external dependencies and no network downloads; every command runs as uid/gid 1001.
  scratch=$(mktemp -d /tmp/arc-swift-smoke.XXXXXX)
  trap 'rm -rf "$scratch"' EXIT
  mkdir -p "$scratch/Sources/RunnerSmoke" "$scratch/Tests/RunnerSmokeTests"
  cat > "$scratch/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RunnerSmoke",
    targets: [
        .executableTarget(name: "RunnerSmoke"),
        .testTarget(name: "RunnerSmokeTests", dependencies: ["RunnerSmoke"]),
    ]
)
PACKAGE
  cat > "$scratch/Sources/RunnerSmoke/RunnerSmoke.swift" <<'SOURCE'
import Foundation
func greeting(_ name: String) -> String { ["Hello", name].joined(separator: ", ") }
@main struct RunnerSmoke {
    static func main() {
        let data = Data(greeting("runner").utf8)
        print("Foundation linked: " + String(decoding: data, as: UTF8.self))
    }
}
SOURCE
  cat > "$scratch/Tests/RunnerSmokeTests/RunnerSmokeTests.swift" <<'TEST'
import Foundation
import Testing
@testable import RunnerSmoke
@Test func foundationRoundTrip() {
    #expect(greeting("runner") == "Hello, runner")
    let data = Data(greeting("runner").utf8)
    #expect(String(data: data, encoding: .utf8) == "Hello, runner")
}
TEST
  cd "$scratch"
  swift build --jobs 2
  output=$(.build/debug/RunnerSmoke)
  printf '%s\n' "$output"
  test "$output" = 'Foundation linked: Hello, runner'
  swift test --jobs 2
  cd /home/runner
  rm -rf "$scratch"
  trap - EXIT
  caddy version
  test "$(caddy version | cut -d ' ' -f 1)" = "v$EXPECTED_CADDY"
  buildctl --version
  [[ $(buildctl --version) == *" v$EXPECTED_BUILDCTL "* ]]
  kubectl version --client
  test "$(kubectl version --client -o json | jq -r .clientVersion.gitVersion)" = "v$EXPECTED_KUBECTL"
fi

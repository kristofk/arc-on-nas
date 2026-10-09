#!/usr/bin/env bash
# warm.sh: start a consumer repository's CI workflow by hand, to fill or refresh the warm cache.
#
# The cache is warmed by the consumer's own workflow, not by anything in the cluster: every run
# on the self-hosted scale set builds into the cache, and examples/workflow.yml also runs on a
# weekly schedule. Use this after something empties the cache: a new toolchain image (the
# toolchain version is part of what is cached), a pruned or deleted cache directory, a new
# repository. Runs wherever the GitHub CLI (gh) is logged in; needs nothing from this host.
#
# Usage: scripts/warm.sh --repo OWNER/REPO [--workflow ci.yml] [--ref main]
set -euo pipefail

repo=""
workflow=ci.yml
ref=main
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=$2; shift 2 ;;
    --workflow) workflow=$2; shift 2 ;;
    --ref) ref=$2; shift 2 ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] || { echo "--repo OWNER/REPO is required" >&2; exit 2; }
command -v gh >/dev/null || { echo "The GitHub CLI (gh) is required: https://cli.github.com" >&2; exit 1; }

# The workflow needs a workflow_dispatch trigger (examples/workflow.yml has one).
gh workflow run "$workflow" --repo "$repo" --ref "$ref"
echo "Started $workflow on $repo@$ref. Follow it with: gh run list --repo $repo --workflow $workflow"

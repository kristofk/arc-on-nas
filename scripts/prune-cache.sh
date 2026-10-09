#!/usr/bin/env bash
# prune-cache.sh: delete parts of the warm cache that no job has touched for a while.
#
# The cache grows: build folders of packages or branches that no longer exist, and downloaded
# dependencies no build uses any more. This removes every entry two levels below the cache
# directory (for example swiftpm-build/<package> or swiftpm-cache/<item>) in which no file was
# modified for --days days. Entries in use are touched by every build and survive.
#
# Dry run by default: it lists what it would delete. --apply deletes. Run it on the host, as a
# user that may delete the runner's files (root, or uid 1001), for example weekly from the host's
# task scheduler. Deleting anything here only costs a slower (cold) build.
#
# It refuses a directory that is not owned by uid 1001 (the runner, as the Quick start creates
# claim directories), so a mistyped path is not pruned; --force overrides that.
#
# Usage: scripts/prune-cache.sh [--days 30] [--apply] [--force] CACHE_DIR/<claim directory>
#   e.g. scripts/prune-cache.sh --days 30 --apply /path/to/ci-cache/default
set -euo pipefail

days=30
apply=0
force=0
dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days=${2:-}; shift $(( $# > 1 ? 2 : 1 )) ;;
    --apply) apply=1; shift ;;
    --force) force=1; shift ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    -*) echo "unknown argument: $1" >&2; exit 2 ;;
    *) dir=$1; shift ;;
  esac
done
[ -n "$dir" ] || { echo "Give the cache claim's directory, e.g. /path/to/ci-cache/default" >&2; exit 2; }
case "$days" in ''|*[!0-9]*) echo "--days must be a whole number" >&2; exit 2 ;; esac
dir=$(cd "$dir" && pwd -P)
# Refuse anything that is obviously not a cache directory.
case "$dir" in /|/bin|/boot|/dev|/etc|/home|/lib|/proc|/root|/run|/sys|/usr|/var) echo "Refusing to prune $dir" >&2; exit 2 ;; esac
if [ "$(stat -c %u "$dir")" != 1001 ] && [ "$force" -eq 0 ]; then
  echo "Refusing: $dir is not owned by uid 1001, so it does not look like a cache claim directory (--force to prune anyway)." >&2
  exit 2
fi

total=0
while IFS= read -r -d '' entry; do
  # Anything modified in the last $days days keeps the whole entry.
  if [ -z "$(find "$entry" -mtime -"$days" -print -quit 2>/dev/null)" ]; then
    size=$(du -sk "$entry" 2>/dev/null | cut -f1)
    total=$(( total + ${size:-0} ))
    if [ "$apply" -eq 1 ]; then
      rm -rf -- "$entry"
      echo "deleted  $(( ${size:-0} / 1024 )) MiB  $entry"
    else
      echo "would delete  $(( ${size:-0} / 1024 )) MiB  $entry"
    fi
  fi
done < <(find "$dir" -mindepth 2 -maxdepth 2 -print0)

if [ "$apply" -eq 1 ]; then
  echo "Freed about $(( total / 1024 )) MiB."
else
  echo "Would free about $(( total / 1024 )) MiB. Run again with --apply to delete."
fi

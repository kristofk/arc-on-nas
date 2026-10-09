#!/usr/bin/env bash
# preflight.sh: check that this host can run the stack, before the first `docker compose up`.
#
# Prints facts and a verdict per check (PASS, WARN, FAIL, INFO). Changes nothing on the host: the
# only side effect is the overlayfs test, which creates a throwaway Docker volume and container
# and removes both. Exits 1 if any check FAILs.
#
# Usage: scripts/preflight.sh            (as a user that may run docker)
#        DOCKER="sudo docker" scripts/preflight.sh
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
read -ra docker <<< "${DOCKER:-docker}"
# The stack network (docker-compose.yml) and a small image for the overlayfs test.
subnet=172.31.250.0/24
test_image=alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

failed=0
say() { printf '%-5s %s\n' "$1" "$2"; }
pass() { say PASS "$1"; }
warn() { say WARN "$1"; }
fail() { say FAIL "$1"; failed=1; }
info() { say INFO "$1"; }

# "a.b.c.d/n" -> "first last" as integers.
cidr_range() {
  local ip=${1%/*} bits=${1#*/} a b c d
  [ "$bits" = "$1" ] && bits=32
  IFS=. read -r a b c d <<< "$ip"
  local n=$(( (a << 24) | (b << 16) | (c << 8) | d ))
  local size=$(( 1 << (32 - bits) ))
  local first=$(( n & ~(size - 1) & 0xFFFFFFFF ))
  echo "$first $(( first + size - 1 ))"
}
overlaps() {
  local a1 a2 b1 b2
  read -r a1 a2 <<< "$(cidr_range "$1")"
  read -r b1 b2 <<< "$(cidr_range "$2")"
  [ "$a1" -le "$b2" ] && [ "$b1" -le "$a2" ]
}
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]; }

echo "== Kernel and cgroups"
kernel=$(uname -r)
info "kernel $kernel, $(uname -m)"
fs=$(stat -fc %T /sys/fs/cgroup 2>/dev/null || echo unknown)
if [ "$fs" = cgroup2fs ]; then
  pass "cgroup v2 (unified hierarchy)"
else
  fail "cgroup filesystem is '$fs', not cgroup v2; this stack is written for cgroup v2"
fi
if [ -r /sys/fs/cgroup/cgroup.controllers ]; then
  controllers=$(cat /sys/fs/cgroup/cgroup.controllers)
  missing=""
  for c in cpu memory pids cpuset; do
    case " $controllers " in *" $c "*) ;; *) missing="$missing $c" ;; esac
  done
  if [ -z "$missing" ]; then pass "cgroup controllers: $controllers"; else fail "cgroup controllers missing:$missing"; fi
fi
for m in overlay br_netfilter nf_conntrack; do
  if [ -d "/sys/module/$m" ]; then pass "kernel module $m loaded"; else warn "kernel module $m not loaded (k3s will try to load it; load it on the host if the node does not become Ready)"; fi
done

echo "== Kernel settings"
for s in fs.inotify.max_user_watches:524288 fs.inotify.max_user_instances:512; do
  name=${s%%:*} want=${s#*:}
  have=$(cat "/proc/sys/${name//.//}" 2>/dev/null || echo 0)
  if [ "$have" -ge "$want" ]; then pass "$name = $have"; else warn "$name = $have; raise it to at least $want persistently on the host (README, \"Requirements\")"; fi
done
# The kubelet sets these host-wide on start (README, "Security posture"). Shown so you can compare.
for name in vm.overcommit_memory vm.panic_on_oom kernel.panic kernel.panic_on_oops kernel.keys.root_maxkeys kernel.keys.root_maxbytes; do
  info "$name = $(cat "/proc/sys/${name//.//}" 2>/dev/null || echo '?')  (the kubelet sets $(case $name in vm.overcommit_memory) echo 1;; vm.panic_on_oom) echo 0;; kernel.panic) echo 10;; kernel.panic_on_oops) echo 1;; kernel.keys.root_maxkeys) echo 1000000;; kernel.keys.root_maxbytes) echo 25000000;; esac))"
done

echo "== Docker"
if ! "${docker[@]}" info >/dev/null 2>&1; then
  fail "cannot talk to Docker as this user; run as a user in the docker group, or DOCKER=\"sudo docker\" $0"
  echo; echo "Stopping: the remaining checks need Docker."; exit 1
fi
server=$("${docker[@]}" version --format '{{.Server.Version}}' 2>/dev/null)
if version_ge "$server" 27.0.0; then pass "Docker Engine $server"; else fail "Docker Engine $server; 27 or later is required"; fi
compose=$("${docker[@]}" compose version --short 2>/dev/null || true)
compose=${compose#v}
if [ -n "$compose" ] && version_ge "$compose" 2.24.0; then pass "Docker Compose $compose"; else fail "Docker Compose v2 (2.24 or later) not found (have: '${compose:-none}')"; fi
driver=$("${docker[@]}" info --format '{{.Driver}}')
cgdriver=$("${docker[@]}" info --format '{{.CgroupDriver}}')
cgversion=$("${docker[@]}" info --format '{{.CgroupVersion}}')
rootdir=$("${docker[@]}" info --format '{{.DockerRootDir}}')
secopts=$("${docker[@]}" info --format '{{join .SecurityOptions " "}}')
if [ "$driver" = overlay2 ] || [ "$driver" = overlayfs ]; then pass "storage driver $driver"; else warn "storage driver $driver; only overlay2 is tested"; fi
info "cgroup driver $cgdriver, cgroup version $cgversion"
case "$secopts" in
  *rootless*) fail "Docker runs rootless; a privileged k3s node needs rootful Docker" ;;
  *userns*) warn "Docker remaps user namespaces; docker-compose.yml opts the node out with userns_mode: host" ;;
  *) pass "Docker is rootful without user-namespace remapping" ;;
esac
rootfs=$(stat -fc %T "$rootdir" 2>/dev/null || echo "unknown (no permission?)")
info "Docker root $rootdir is on $rootfs"
if [ "$rootfs" = zfs ]; then
  info "ZFS: overlayfs on ZFS needs OpenZFS 2.2 or later ($(cat /sys/module/zfs/version 2>/dev/null || echo 'version unknown')); the next check and scripts/trial.sh are the real test"
fi

echo "== overlayfs on a Docker volume (what the node's containerd does)"
vol="arc-on-nas-preflight-$$"
if "${docker[@]}" run --rm --privileged -v "$vol:/v" "$test_image" sh -c \
     'mkdir -p /v/l /v/u /v/w /v/m && mount -t overlay overlay -o lowerdir=/v/l,upperdir=/v/u,workdir=/v/w /v/m && touch /v/m/x && umount /v/m' \
     >/dev/null 2>&1; then
  pass "overlayfs mounts on a Docker volume"
else
  fail "overlayfs does not mount on a Docker volume here; set K3S_SNAPSHOTTER=native in .env (README, \"Troubleshooting\")"
fi
"${docker[@]}" volume rm -f "$vol" >/dev/null 2>&1 || true

echo "== Resources"
cpus=$(nproc --all 2>/dev/null || getconf _NPROCESSORS_ONLN)
memtotal_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
memavail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
swap_kb=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
info "CPUs: $cpus (the kubelet's CPU capacity)"
info "MemTotal: $(( memtotal_kb / 1024 )) MiB (the kubelet's memory capacity); available now: $(( memavail_kb / 1024 )) MiB; swap: $(( swap_kb / 1024 )) MiB"
info "load average: $(cut -d' ' -f1-3 /proc/loadavg)"
df_line=$(df -Pk "$rootdir" 2>/dev/null | awk 'NR==2 {print int($4/1024/1024) " GiB free of " int($2/1024/1024) " GiB"}')
info "Docker root: ${df_line:-unknown}"

if [ -f "$root/.env" ]; then
  k3s_cpus=$(sed -n 's/^K3S_CPUS=//p' "$root/.env" | tail -n 1)
  if [ -n "$k3s_cpus" ]; then
    if awk -v a="$k3s_cpus" -v b="$cpus" 'BEGIN { exit !(a > b) }'; then
      fail "K3S_CPUS=$k3s_cpus in .env is more than the host's $cpus CPUs; Docker will refuse to start the node"
    else
      pass "K3S_CPUS=$k3s_cpus fits the host's $cpus CPUs"
    fi
  fi
  cache_dir=$(sed -n 's/^CACHE_DIR=//p' "$root/.env" | tail -n 1)
  if [ -n "$cache_dir" ] && [ -d "$cache_dir" ]; then
    info "cache directory $cache_dir: $(df -Pk "$cache_dir" | awk 'NR==2 {print int($4/1024/1024) " GiB free"}'), on $(stat -fc %T "$cache_dir")"
    if [ -d "$cache_dir/default" ]; then
      owner=$(stat -c %u:%g "$cache_dir/default")
      if [ "$owner" = 1001:1001 ]; then pass "$cache_dir/default is owned by 1001:1001"; else fail "$cache_dir/default is owned by $owner; the runner (1001:1001) cannot write it"; fi
    else
      fail "$cache_dir/default does not exist (README, \"Quick start\")"
    fi
  else
    fail "CACHE_DIR '${cache_dir}' from .env is not a directory"
  fi
else
  info "no .env yet: skipping the cache directory checks"
fi
if [ -d "$root/kubeconfig" ]; then
  perm=$(stat -c '%a %u' "$root/kubeconfig")
  if [ "$perm" = "700 0" ]; then pass "kubeconfig/ is root-owned, mode 700"; else warn "kubeconfig/ is mode/owner '$perm'; make it root-owned, mode 700 (README, \"Quick start\")"; fi
else
  info "kubeconfig/ does not exist yet"
fi

echo "== Addresses"
conflict=""
while read -r net; do
  [ -z "$net" ] && continue
  name=$("${docker[@]}" network inspect -f '{{.Name}}' "$net")
  [ "$name" = ci_runners ] && continue
  for s in $("${docker[@]}" network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$net"); do
    case "$s" in *:*) continue ;; esac
    if overlaps "$s" "$subnet"; then conflict="$conflict Docker network $name ($s);"; fi
  done
done < <("${docker[@]}" network ls -q)
if command -v ip >/dev/null 2>&1; then
  while read -r dst _; do
    case "$dst" in default|*:*) continue ;; esac
    case "$dst" in */*) ;; *) dst="$dst/32" ;; esac
    if overlaps "$dst" "$subnet"; then conflict="$conflict host route $dst;"; fi
  done < <(ip -4 route show table main 2>/dev/null | grep -v 'br-ci-runners')
fi
if [ -z "$conflict" ]; then
  pass "stack subnet $subnet is free"
else
  fail "stack subnet $subnet overlaps:$conflict change it (docker-compose.yml header)"
fi

echo
if [ "$failed" -eq 0 ]; then
  echo "No check failed. Next: scripts/trial.sh."
else
  echo "Some checks failed; fix them before continuing."
fi
exit "$failed"

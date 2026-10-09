#!/usr/bin/env bash
# preflight.sh: check that this host can run the stack, before the first `docker compose up`.
#
# Prints facts and a verdict per check (PASS, WARN, FAIL, INFO). Changes nothing on the host: the
# only side effect is the overlayfs test, which creates a throwaway Docker volume and container
# and removes both. Exits 1 if any check FAILs.
#
# Usage: scripts/preflight.sh            (as a user that may run docker)
#        DOCKER="sudo docker" scripts/preflight.sh
#        BUDGET_CPUS=4 BUDGET_GIB=8 scripts/preflight.sh
#
# With BUDGET_CPUS and BUDGET_GIB (whole numbers: what this host gives CI), it also prints the
# four K3S_* sizing lines for .env (README, "Sizing"). With a .env, it checks the sizing in it.
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
# The filesystem type under a path (stat -f reports ext4 as "ext2/ext3").
fstype() { findmnt -no FSTYPE -T "$1" 2>/dev/null || stat -fc %T "$1" 2>/dev/null || echo "unknown (no permission?)"; }
# Sizes as whole MiB and CPU as millicores, from Docker's notation (17g, 17408m, bytes) and
# Kubernetes' quantities (17664Mi, 17Gi, 18G, 6500m, 6.5). Prints nothing if it cannot parse.
to_mib() {
  awk -v v="$1" -v mode="$2" 'BEGIN {
    if (!match(v, /^[0-9]+(\.[0-9]+)?/)) exit
    n = substr(v, 1, RLENGTH); u = substr(v, RLENGTH + 1)
    f["Ki"] = 1/1024; f["Mi"] = 1; f["Gi"] = 1024; f["Ti"] = 1048576
    f["k"] = 1000/1048576; f["M"] = 1e6/1048576; f["G"] = 1e9/1048576; f["T"] = 1e12/1048576
    f[""] = 1/1048576
    lu = tolower(u); sub(/b$/, "", lu)
    d["k"] = 1/1024; d["m"] = 1; d["g"] = 1024; d["t"] = 1048576; d[""] = 1/1048576
    if (mode == "docker" && (lu in d)) { printf "%d", n * d[lu]; exit }
    if (mode == "k8s" && (u in f)) printf "%d", n * f[u]
  }'
}
to_millicpu() {
  case "$1" in
    *m) echo "${1%m}" ;;
    *) awk -v v="$1" 'BEGIN { if (v ~ /^[0-9]+(\.[0-9]+)?$/) printf "%d", v * 1000 }' ;;
  esac
}
# One resource from a kubelet reservation such as cpu=6500m,memory=17664Mi.
reserved() { tr ',' '\n' <<< "$1" | sed -n "s/^$2=//p" | head -n 1; }

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
# The kubelet sets these host-wide at every start (README, "Security posture"). Shown so you can
# compare, and record them.
for name in vm.overcommit_memory vm.panic_on_oom kernel.panic kernel.panic_on_oops kernel.keys.root_maxkeys kernel.keys.root_maxbytes; do
  info "$name = $(cat "/proc/sys/${name//.//}" 2>/dev/null || echo '?')  (the kubelet sets $(case $name in vm.overcommit_memory) echo 1;; vm.panic_on_oom) echo 0;; kernel.panic) echo 10;; kernel.panic_on_oops) echo 1;; kernel.keys.root_maxkeys) echo 1000000;; kernel.keys.root_maxbytes) echo 25000000;; esac))"
done

info "the kubelet overwrites these at every start and they stay after 'docker compose down'; record yours first (README, \"Security posture\")"

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
rootfs=$(fstype "$rootdir")
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
memtotal=$(( memtotal_kb / 1024 ))
# The control plane's reservation and the headroom above allocatable + kube-reserved, as in
# README "Sizing" and .env.example.
kube_cpu=500 kube_mem=1536 head_cpu=500 head_mem=2304

budget_cpus=${BUDGET_CPUS:-} budget_gib=${BUDGET_GIB:-}
if [ -n "$budget_cpus$budget_gib" ]; then
  case "$budget_cpus$budget_gib" in
    *[!0-9]*) fail "BUDGET_CPUS and BUDGET_GIB must both be whole numbers (have '$budget_cpus', '$budget_gib')" ;;
    *)
      if [ -z "$budget_cpus" ] || [ -z "$budget_gib" ]; then
        fail "give both BUDGET_CPUS and BUDGET_GIB"
      else
        alloc_cpu=$(( budget_cpus * 1000 - kube_cpu - head_cpu ))
        alloc_mem=$(( budget_gib * 1024 - kube_mem - head_mem ))
        if [ "$budget_cpus" -gt "$cpus" ] || [ "$(( budget_gib * 1024 ))" -gt "$memtotal" ]; then
          fail "a budget of $budget_cpus CPUs and $budget_gib GiB is more than this host has ($cpus CPUs, $memtotal MiB)"
        elif [ "$alloc_cpu" -lt 1000 ] || [ "$alloc_mem" -lt 1024 ]; then
          fail "a budget of $budget_cpus CPUs and $budget_gib GiB leaves ${alloc_cpu}m CPU and ${alloc_mem}Mi for pods; give CI more"
        else
          info "for a budget of $budget_cpus CPUs and $budget_gib GiB, put these in .env (allocatable ${alloc_cpu}m CPU, ${alloc_mem}Mi):"
          echo "      K3S_CPUS=$budget_cpus"
          echo "      K3S_MEMORY=${budget_gib}g"
          echo "      K3S_SYSTEM_RESERVED=cpu=$(( cpus * 1000 - alloc_cpu - kube_cpu ))m,memory=$(( memtotal - alloc_mem - kube_mem ))Mi"
          echo "      K3S_KUBE_RESERVED=cpu=${kube_cpu}m,memory=${kube_mem}Mi"
          info "of the allocatable, the system pods take about 600m CPU and 700Mi; the rest is for runner pods"
        fi
      fi ;;
  esac
else
  info "for the K3S_* sizing lines for .env: BUDGET_CPUS=<n> BUDGET_GIB=<n> $0 (README, \"Sizing\")"
fi

if [ -f "$root/.env" ]; then
  env_value() { sed -n "s/^$1=//p" "$root/.env" | tail -n 1; }
  k3s_cpus=$(env_value K3S_CPUS)
  if [ -n "$k3s_cpus" ]; then
    if awk -v a="$k3s_cpus" -v b="$cpus" 'BEGIN { exit !(a > b) }'; then
      fail "K3S_CPUS=$k3s_cpus in .env is more than the host's $cpus CPUs; Docker will refuse to start the node"
    else
      pass "K3S_CPUS=$k3s_cpus fits the host's $cpus CPUs"
    fi
  fi
  k3s_memory=$(env_value K3S_MEMORY)
  cap_mem=""
  if [ -n "$k3s_memory" ]; then
    cap_mem=$(to_mib "$k3s_memory" docker)
    if [ -z "$cap_mem" ]; then
      warn "cannot read K3S_MEMORY=$k3s_memory in .env"
    elif [ "$cap_mem" -gt "$memtotal" ]; then
      fail "K3S_MEMORY=$k3s_memory in .env is more than the host's $memtotal MiB"
    else
      pass "K3S_MEMORY=$k3s_memory fits the host's $memtotal MiB"
    fi
  fi
  sys_res=$(env_value K3S_SYSTEM_RESERVED) kube_res=$(env_value K3S_KUBE_RESERVED)
  if [ -n "$sys_res" ] && [ -n "$kube_res" ]; then
    sys_c=$(to_millicpu "$(reserved "$sys_res" cpu)") kube_c=$(to_millicpu "$(reserved "$kube_res" cpu)")
    sys_m=$(to_mib "$(reserved "$sys_res" memory)" k8s) kube_m=$(to_mib "$(reserved "$kube_res" memory)" k8s)
    if [ -z "$sys_c" ] || [ -z "$kube_c" ] || [ -z "$sys_m" ] || [ -z "$kube_m" ]; then
      warn "cannot read cpu= and memory= in K3S_SYSTEM_RESERVED and K3S_KUBE_RESERVED; not checking the sizing"
    else
      alloc_c=$(( cpus * 1000 - sys_c - kube_c )) alloc_m=$(( memtotal - sys_m - kube_m ))
      if [ "$alloc_c" -le 0 ] || [ "$alloc_m" -le 0 ]; then
        fail "the reservations in .env leave allocatable ${alloc_c}m CPU and ${alloc_m}Mi on this host; no pod would be admitted (README, \"Sizing\")"
      else
        info "allocatable with .env on this host: ${alloc_c}m CPU, ${alloc_m}Mi"
        if [ -n "$cap_mem" ] && [ "$(( alloc_m + kube_m ))" -ge "$cap_mem" ]; then
          warn "allocatable + kube-reserved (${alloc_m}Mi + ${kube_m}Mi) is not below K3S_MEMORY ($cap_mem MiB): full pods can make the OOM killer pick k3s (README, \"Sizing\")"
        fi
        if [ -n "$k3s_cpus" ] && awk -v a="$(( alloc_c + kube_c ))" -v b="$k3s_cpus" 'BEGIN { exit !(a > b * 1000) }'; then
          warn "allocatable + kube-reserved ($(( alloc_c + kube_c ))m CPU) is more than K3S_CPUS=$k3s_cpus: full pods get less CPU than they requested"
        fi
      fi
    fi
  fi
  cache_dir=$(env_value CACHE_DIR)
  if [ -n "$cache_dir" ] && [ -d "$cache_dir" ]; then
    info "cache directory $cache_dir: $(df -Pk "$cache_dir" | awk 'NR==2 {print int($4/1024/1024) " GiB free"}'), on $(fstype "$cache_dir")"
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

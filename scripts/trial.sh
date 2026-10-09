#!/usr/bin/env bash
# trial.sh: start a throwaway k3s node on this host, see whether it works, and remove it.
#
# This is the real test of the host's kernel, cgroups and storage for a Kubernetes node in Docker:
# a node container named k3s-trial with the same image and k3s flags as docker-compose.yml (but
# no proxy, no caps and no reservations), waits until the node is Ready, runs one pod, then
# reports the control plane's memory, the node's capacity, suspicious log lines, and any host
# kernel setting the kubelet changed. It always removes the container and its volume at the end,
# unless --keep is given.
#
# The kubelet sets some host-wide kernel settings when it starts (README, "Security posture").
# The script records them before and reports any change. Run as root to have them restored.
#
# Usage: scripts/trial.sh [--snapshotter native] [--keep] [--timeout SECONDS]
#        DOCKER="sudo docker" scripts/trial.sh
set -euo pipefail

read -ra docker <<< "${DOCKER:-docker}"
# Keep in step with docker-compose.yml (scripts/check-consistency.sh checks it).
image=rancher/k3s:v1.36.5-k3s1@sha256:057cfd5a9d51b89f1f0ee139c28d5d5fdd5aa7ddeac2742a0ba90c6dbc0329bb
pod_image=alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
name=k3s-trial
snapshotter=overlayfs
keep=0
timeout=300

while [ $# -gt 0 ]; do
  case "$1" in
    --snapshotter) snapshotter=$2; shift 2 ;;
    --keep) keep=1; shift ;;
    --timeout) timeout=$2; shift 2 ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

sysctls="vm.overcommit_memory vm.panic_on_oom kernel.panic kernel.panic_on_oops kernel.keys.root_maxkeys kernel.keys.root_maxbytes"
declare -A before
for s in $sysctls; do before[$s]=$(cat "/proc/sys/${s//.//}"); done

kubectl() { "${docker[@]}" exec "$name" kubectl "$@"; }

cleanup() {
  status=$?
  if [ "$keep" -eq 1 ]; then
    echo "Kept: $name. Remove it with: ${docker[*]} rm -f $name && ${docker[*]} volume rm $name"
  else
    echo "== Removing the trial node"
    "${docker[@]}" rm -f "$name" >/dev/null 2>&1 || true
    "${docker[@]}" volume rm -f "$name" >/dev/null 2>&1 || true
  fi
  echo "== Host kernel settings the kubelet changed"
  changed=0
  for s in $sysctls; do
    now=$(cat "/proc/sys/${s//.//}")
    if [ "$now" != "${before[$s]}" ]; then
      changed=1
      echo "$s: ${before[$s]} -> $now"
      if [ "$(id -u)" -eq 0 ] && [ "$keep" -eq 0 ]; then
        echo "${before[$s]}" > "/proc/sys/${s//.//}" && echo "  restored to ${before[$s]}"
      else
        echo "  restore with: sudo sysctl -w $s=${before[$s]}"
      fi
    fi
  done
  [ "$changed" -eq 0 ] && echo "none"
  exit "$status"
}

if "${docker[@]}" container inspect "$name" >/dev/null 2>&1; then
  echo "A container named $name already exists; remove it first." >&2
  exit 1
fi
trap cleanup EXIT

echo "== Starting $name ($image, snapshotter $snapshotter)"
"${docker[@]}" run -d --name "$name" --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /var/run \
  -v "$name:/var/lib/rancher/k3s" \
  "$image" server \
  --node-name=k3s-trial --disable=traefik,servicelb --disable-helm-controller \
  --snapshotter="$snapshotter" --kube-proxy-arg=conntrack-max-per-core=0 >/dev/null

echo "== Waiting for the node to be Ready (up to ${timeout}s)"
start=$(date +%s)
until kubectl get node k3s-trial -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; do
  if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
    echo "The node did not become Ready. Its log:" >&2
    "${docker[@]}" logs --tail 80 "$name" >&2 || true
    exit 1
  fi
  sleep 5
done
echo "Ready after $(( $(date +%s) - start ))s"

echo "== Waiting for the system pods"
# k3s creates its bundled components a few seconds after the node registers.
for _ in $(seq 1 60); do
  kubectl -n kube-system get deployment coredns >/dev/null 2>&1 && break
  sleep 2
done
kubectl -n kube-system rollout status deployment/coredns --timeout="${timeout}s"
kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s
kubectl get pods -A -o wide

echo "== A test pod"
# A new cluster creates the default service account a few seconds after it starts.
for _ in $(seq 1 30); do kubectl get serviceaccount default >/dev/null 2>&1 && break; sleep 2; done
kubectl run trial-pod --image="$pod_image" --restart=Never --command -- sh -c 'id; grep -E "^Cap(Eff|Bnd)" /proc/1/status; df -h / | tail -n 1'
if kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/trial-pod --timeout=180s; then
  kubectl logs trial-pod
else
  echo "The test pod did not succeed:" >&2
  kubectl describe pod trial-pod >&2 || true
  exit 1
fi

echo "== The node as the scheduler sees it"
kubectl get node k3s-trial -o jsonpath='capacity:    cpu={.status.capacity.cpu} memory={.status.capacity.memory} pods={.status.capacity.pods}{"\n"}allocatable: cpu={.status.allocatable.cpu} memory={.status.allocatable.memory}{"\n"}'
kubectl get node k3s-trial -o wide

echo "== Control plane overhead (whole container, idle)"
"${docker[@]}" stats --no-stream --format 'cpu {{.CPUPerc}}  memory {{.MemUsage}}  pids {{.PIDs}}' "$name"

echo "== Log lines worth reading (storage, snapshotter, cgroups)"
"${docker[@]}" logs "$name" 2>&1 \
  | grep -iE 'rootfs|snapshotter.*(fail|error)|overlay.*(fail|error)|cadvisor.*(fail|error)|cgroup.*(fail|error)' \
  | grep -viE 'level=info|deprecated|failed to read (memory|cpu)' | head -n 30 || echo "none"

echo
echo "The trial node worked. A 'failed to get rootfs info' line above means the kubelet cannot"
echo "measure the disk on this storage; see README, \"Troubleshooting\"."

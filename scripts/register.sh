#!/usr/bin/env bash
# register.sh: store the GitHub credential the scale sets use, as a Kubernetes Secret.
#
# The credential is read from a file or typed at a prompt, never taken as an argument (arguments
# end up in shell history and in the process list). It travels on standard input into the k3s
# container and is stored only in the cluster, as the Secret named in helm/*.yaml
# (githubConfigSecret). Running it again replaces the Secret.
#
# A personal access token (key github_token):
#   scripts/register.sh                        prompts for the token
#   scripts/register.sh --token-file FILE      reads it from FILE (delete the file afterwards)
# A GitHub App (keys github_app_id, github_app_installation_id, github_app_private_key):
#   scripts/register.sh --app-id ID --installation-id ID --private-key-file FILE.pem
# Options:
#   --name NAME        Secret name (default github-credentials)
#   --namespace NS     namespace (default arc-runners)
#
# Which credential, with which permissions: README, "Adding a repository". Run from anywhere, as
# a user that may run docker (or DOCKER="sudo docker"); the stack must be up.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
read -ra docker <<< "${DOCKER:-docker}"
name=github-credentials
namespace=arc-runners
token_file=""
app_id=""
installation_id=""
key_file=""

usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --token-file) token_file=$2; shift 2 ;;
    --app-id) app_id=$2; shift 2 ;;
    --installation-id) installation_id=$2; shift 2 ;;
    --private-key-file) key_file=$2; shift 2 ;;
    --name) name=$2; shift 2 ;;
    --namespace) namespace=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1 (the credential is never an argument; see --help)" >&2; exit 2 ;;
  esac
done

kubectl() { "${docker[@]}" compose --project-directory "$root" exec -T k3s kubectl "$@"; }

if ! kubectl get namespace "$namespace" >/dev/null; then
  echo "Namespace $namespace not found. Is the stack up and are the manifests applied?" >&2
  exit 1
fi

if [ -n "$app_id$installation_id$key_file" ]; then
  if [ -z "$app_id" ] || [ -z "$installation_id" ] || [ -z "$key_file" ]; then
    echo "A GitHub App needs --app-id, --installation-id and --private-key-file." >&2
    exit 2
  fi
  [ -r "$key_file" ] || { echo "Cannot read $key_file" >&2; exit 1; }
  # The IDs are not secret; the private key goes through standard input.
  kubectl create secret generic "$name" --namespace "$namespace" \
      --from-literal=github_app_id="$app_id" \
      --from-literal=github_app_installation_id="$installation_id" \
      --from-file=github_app_private_key=/dev/stdin \
      --dry-run=client -o yaml < "$key_file" \
    | kubectl apply -f - >/dev/null
  echo "Secret $namespace/$name holds the GitHub App's credentials."
else
  if [ -n "$token_file" ]; then
    [ -r "$token_file" ] || { echo "Cannot read $token_file" >&2; exit 1; }
    token=$(head -n 1 "$token_file")
  else
    [ -t 0 ] || { echo "No terminal to prompt on; use --token-file." >&2; exit 2; }
    read -rsp "GitHub token (not shown): " token
    echo
  fi
  # Strip whitespace a copy and paste may have added.
  token=$(printf '%s' "$token" | tr -d '[:space:]')
  [ -n "$token" ] || { echo "The token is empty." >&2; exit 1; }
  printf '%s' "$token" \
    | kubectl create secret generic "$name" --namespace "$namespace" \
        --from-file=github_token=/dev/stdin --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
  unset token
  echo "Secret $namespace/$name holds the token."
fi

# The listener of each scale set reads the credential when it starts.
cat <<EOF
If scale sets are already installed, restart their listeners to use the new credential:
  docker compose exec k3s kubectl -n arc-systems delete pod -l app.kubernetes.io/component=runner-scale-set-listener
EOF

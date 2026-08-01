#!/usr/bin/env bash
set -Eeuo pipefail

readonly script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly repo_root=$(cd -- "$script_dir/.." && pwd)
readonly deploy_user=ecomex
readonly -a hosts=(hl03 hl02 hl01)

declare -Ar host_addresses=(
  [hl01]=10.20.50.11
  [hl02]=10.20.50.12
  [hl03]=10.20.50.13
)

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy-homelab.sh

Build and deploy all homelab hosts from nix-ai in this order:
  hl03 -> hl02 -> hl01

The script requires a clean main checkout matching origin/main and an
interactive terminal for the target hosts' sudo password prompts.
EOF
}

if [[ ${1-} == "--help" || ${1-} == "-h" ]]; then
  usage
  exit 0
fi

[[ $# -eq 0 ]] || {
  usage >&2
  exit 2
}

[[ $(hostname -s) == "nix-ai" ]] || die "run this script on nix-ai"
[[ -t 0 && -t 1 ]] || die "an interactive terminal is required"

for command in git nixos-rebuild ssh; do
  command -v "$command" >/dev/null || die "required command not found: $command"
done

cd "$repo_root"

[[ -z $(git status --porcelain) ]] || die "Git worktree is dirty; commit or stash all changes first"
[[ $(git branch --show-current) == "main" ]] || die "the checked-out branch must be main"

printf 'Fetching origin/main...\n'
git fetch --quiet origin main

readonly local_revision=$(git rev-parse HEAD)
readonly remote_revision=$(git rev-parse origin/main)
[[ $local_revision == "$remote_revision" ]] || \
  die "local main does not match origin/main; update the checkout before deploying"

printf 'Deploying revision %s\n\n' "$(git rev-parse --short=12 HEAD)"

printf 'Checking target connectivity and identity...\n'
for host in "${hosts[@]}"; do
  address=${host_addresses[$host]}
  remote_host=$(ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    "$deploy_user@$address" \
    hostname -s)
  [[ $remote_host == "$host" ]] || \
    die "$address identified itself as '$remote_host', expected '$host'"
  printf '  %-4s %s: ready\n' "$host" "$address"
done

printf '\nBuilding every configuration before the first switch...\n'
for host in "${hosts[@]}"; do
  printf '\n==> Building %s\n' "$host"
  nixos-rebuild build --flake ".#$host"
done

printf '\nAll builds succeeded. Starting staggered deployment...\n'
for host in "${hosts[@]}"; do
  address=${host_addresses[$host]}
  target="$deploy_user@$address"

  printf '\n==> Deploying %s (%s)\n' "$host" "$address"
  nixos-rebuild switch \
    --flake ".#$host" \
    --target-host "$target" \
    --ask-sudo-password

  failed_units=$(ssh -o BatchMode=yes "$target" \
    systemctl --failed --no-legend --plain --no-pager)
  if [[ -n $failed_units ]]; then
    printf '\nFailed units on %s:\n%s\n' "$host" "$failed_units" >&2
    die "deployment stopped after $host"
  fi

  generation=$(ssh -o BatchMode=yes "$target" readlink -f /run/current-system)
  printf '  %s: healthy (%s)\n' "$host" "$generation"
done

printf '\nAll homelab hosts were deployed successfully.\n'

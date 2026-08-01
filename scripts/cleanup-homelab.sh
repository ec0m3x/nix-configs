#!/usr/bin/env bash
set -Eeuo pipefail

readonly deploy_user=ecomex
readonly retention=7d
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
Usage: ./scripts/cleanup-homelab.sh

Delete Nix generations older than seven days and collect unreachable store
paths on hl03, hl02, hl01 and nix-ai. The shared sudo password is requested
once and passed to every sudo process through stdin.
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

for command in df ssh sudo; do
  command -v "$command" >/dev/null || die "required command not found: $command"
done

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

printf 'Sudo password for %s on nix-ai and hl01-hl03: ' "$deploy_user" >&2
IFS= read -r -s sudo_password </dev/tty
printf '\n' >&2
[[ -n $sudo_password ]] || die "the sudo password must not be empty"
trap 'sudo_password=; unset sudo_password' EXIT

for host in "${hosts[@]}"; do
  address=${host_addresses[$host]}
  target="$deploy_user@$address"

  printf '\n==> Cleaning %s (%s), keeping %s\n' "$host" "$address" "$retention"
  ssh -o BatchMode=yes "$target" df -h /nix/store
  printf '%s\n' "$sudo_password" | ssh -o BatchMode=yes "$target" \
    sudo --stdin --prompt= /run/current-system/sw/bin/nix-collect-garbage \
    --delete-older-than "$retention"
  ssh -o BatchMode=yes "$target" df -h /nix/store
done

printf '\n==> Cleaning nix-ai, keeping %s\n' "$retention"
df -h /nix/store
printf '%s\n' "$sudo_password" | sudo --stdin --prompt= \
  /run/current-system/sw/bin/nix-collect-garbage \
  --delete-older-than "$retention"
df -h /nix/store

printf '\nNix cleanup completed successfully on all homelab hosts and nix-ai.\n'

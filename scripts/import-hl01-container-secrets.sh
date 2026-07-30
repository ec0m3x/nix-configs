#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
secrets_file="$repo_root/secrets/hl01.yaml"
source_host="${HL01_SOURCE_HOST:-ecomex@10.20.50.46}"
sops_cmd=(nix run nixpkgs#sops --)

if [[ "$(hostname)" != "hl02" && "$(hostname)" != "hl03" ]]; then
  printf 'Run this script on hl02 or hl03; their SSH host keys unlock %s.\n' "$secrets_file" >&2
  exit 1
fi

sudo -v

identity_dir="$(mktemp -d)"
identity_fifo="$identity_dir/ssh_host_ed25519_key"
mkfifo -m 600 "$identity_fifo"
cleanup() {
  rm -f "$identity_fifo"
  rmdir "$identity_dir"
}
trap cleanup EXIT

sops_set() {
  local index="$1"
  local writer_pid

  # Open the FIFO inside the background process. Opening it in this shell
  # would block before SOPS has a chance to start its reader.
  sudo sh -c \
    'cat /etc/ssh/ssh_host_ed25519_key > "$1"' \
    sh "$identity_fifo" &
  writer_pid="$!"
  if ! SOPS_AGE_SSH_PRIVATE_KEY_FILE="$identity_fifo" \
    "${sops_cmd[@]}" set --value-stdin "$secrets_file" "$index"; then
    kill "$writer_pid" 2>/dev/null || true
    wait "$writer_pid" 2>/dev/null || true
    return 1
  fi
  wait "$writer_pid"
}

sops_set '["haushaltsbuch_environment"]' < <(
  ssh "$source_host" 'jq -Rs . < /home/ecomex/haushaltsbuch/.env'
)

sops_set '["honcho_environment"]' < <(
  ssh "$source_host" 'jq -Rs . < /home/ecomex/honcho/.env'
)

if ! grep -q '^honcho_postgres_password:' "$secrets_file"; then
  honcho_postgres_password="$(
    od -An -N32 -tx1 /dev/urandom | tr -d '[:space:]'
  )"
  sops_set '["honcho_postgres_password"]' < <(
    jq -Rn --arg value "$honcho_postgres_password" '$value'
  )
  unset honcho_postgres_password
fi

read -r -s -p "GHCR PAT (classic, read:packages only): " ghcr_pull_token
printf '\n'
if [[ -z "$ghcr_pull_token" ]]; then
  printf 'GHCR token must not be empty.\n' >&2
  exit 1
fi
sops_set '["ghcr_pull_token"]' < <(
  jq -Rn --arg value "$ghcr_pull_token" '$value'
)
unset ghcr_pull_token

printf 'Imported and encrypted all hl01 container secrets in %s.\n' "$secrets_file"

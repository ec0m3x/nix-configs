#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
secrets_file="$repo_root/secrets/hl01.yaml"
source_host="${HL01_SOURCE_HOST:-ecomex@10.20.50.46}"
sops_cmd=(nix run nixpkgs#sops --)

if [[ "$(hostname)" != "nix-ai" ]]; then
  printf 'Run this script on nix-ai; its SSH host key unlocks %s.\n' "$secrets_file" >&2
  exit 1
fi

sudo -v
export SOPS_AGE_SSH_PRIVATE_KEY_CMD="sudo cat /etc/ssh/ssh_host_ed25519_key"

ssh "$source_host" 'jq -Rs . < /home/ecomex/haushaltsbuch/.env' |
  "${sops_cmd[@]}" set --value-stdin \
    "$secrets_file" '["haushaltsbuch_environment"]'

ssh "$source_host" 'jq -Rs . < /home/ecomex/honcho/.env' |
  "${sops_cmd[@]}" set --value-stdin \
    "$secrets_file" '["honcho_environment"]'

if ! grep -q '^honcho_postgres_password:' "$secrets_file"; then
  honcho_postgres_password="$(
    od -An -N32 -tx1 /dev/urandom | tr -d '[:space:]'
  )"
  jq -Rn --arg value "$honcho_postgres_password" '$value' |
    "${sops_cmd[@]}" set --value-stdin \
      "$secrets_file" '["honcho_postgres_password"]'
  unset honcho_postgres_password
fi

read -r -s -p "GHCR PAT (classic, read:packages only): " ghcr_pull_token
printf '\n'
if [[ -z "$ghcr_pull_token" ]]; then
  printf 'GHCR token must not be empty.\n' >&2
  exit 1
fi
jq -Rn --arg value "$ghcr_pull_token" '$value' |
  "${sops_cmd[@]}" set --value-stdin \
    "$secrets_file" '["ghcr_pull_token"]'
unset ghcr_pull_token

printf 'Imported and encrypted all hl01 container secrets in %s.\n' "$secrets_file"

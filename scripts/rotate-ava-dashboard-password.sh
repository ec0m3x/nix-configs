#!/usr/bin/env bash
# Rotate the login password of Ava's web dashboard (https://ava.hl.sk4i.com).
#
# The dashboard authenticates against Hermes' bundled `basic` provider, which
# stores a scrypt hash rather than the password itself. The hash lives in
# secrets/hl01.yaml as `ava_dashboard_password_hash`; modules/nixos/ava.nix
# hands it to the container and restarts it via restartUnits, so rotating is a
# commit — nothing has to be done on hl01 itself.
#
# The password is read from the terminal, hashed in-process and never written
# to disk, a variable that survives this script, or the shell history.
#
# Hash parameters mirror plugins/dashboard_auth/basic.hash_password() in the
# pinned image (scrypt, n=2^14, r=8, p=1, dklen=32, 16-byte salt). If a future
# image changes them, verification here still passes but the dashboard would
# reject the login — check that function after an image bump.
#
# Existing browser sessions survive a password change: session cookies are
# signed with `ava_dashboard_session_secret`, which is independent of the
# password. Pass --rotate-sessions to invalidate them as well, which is what
# you want if a session may have leaked rather than just the password.
#
# Usage:
#   scripts/rotate-ava-dashboard-password.sh                    # commit only
#   scripts/rotate-ava-dashboard-password.sh --push             # commit and push (GitOps deploys)
#   scripts/rotate-ava-dashboard-password.sh --rotate-sessions  # also sign out everyone
#   scripts/rotate-ava-dashboard-password.sh --dry-run          # hash and verify, write nothing
set -euo pipefail

readonly SECRETS="secrets/hl01.yaml"
readonly HASH_KEY="ava_dashboard_password_hash"
readonly SECRET_KEY="ava_dashboard_session_secret"
readonly MIN_LENGTH=12

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

push=false
rotate_sessions=false
dry_run=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) push=true ;;
    --rotate-sessions) rotate_sessions=true ;;
    --dry-run) dry_run=true ;;
    -h|--help)
      sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 64
      ;;
  esac
  shift
done

for tool in sops python3 git openssl; do
  command -v "$tool" >/dev/null || {
    printf '%s is required.\n' "$tool" >&2
    exit 69
  }
done

# sops rewrites the whole file, so unrelated pending edits would be swept into
# the rotation commit.
if [[ "$dry_run" == false ]]; then
  if ! git diff --quiet -- "$SECRETS" || ! git diff --cached --quiet -- "$SECRETS"; then
    printf '%s has uncommitted changes; commit or stash them first.\n' "$SECRETS" >&2
    exit 1
  fi
fi

# A plaintext HERMES_DASHBOARD_BASIC_AUTH_PASSWORD anywhere in the environment
# takes precedence over the hash, so rotating the hash would silently have no
# effect. Catch that before doing any work.
if sops decrypt "$SECRETS" | grep -q 'HERMES_DASHBOARD_BASIC_AUTH_PASSWORD='; then
  printf 'A plaintext HERMES_DASHBOARD_BASIC_AUTH_PASSWORD is set in %s.\n' "$SECRETS" >&2
  printf 'It overrides the hash — remove it first, otherwise this rotation does nothing.\n' >&2
  exit 1
fi

read -rsp "New dashboard password for user 'ecomex': " pw
printf '\n'
read -rsp "Repeat: " pw_repeat
printf '\n'
[[ "$pw" == "$pw_repeat" ]] || {
  printf 'Passwords do not match.\n' >&2
  exit 1
}
[[ "${#pw}" -ge "$MIN_LENGTH" ]] || {
  printf 'Use at least %d characters.\n' "$MIN_LENGTH" >&2
  exit 1
}

# Hash and verify in one process: a hash that does not verify against the
# password just typed means the parameters drifted, and pinning it would lock
# the dashboard out.
hash="$(PW="$pw" python3 - <<'PY'
import base64, hashlib, hmac, os, secrets, sys

pw = os.environ["PW"].encode()
salt = secrets.token_bytes(16)
params = dict(n=2**14, r=8, p=1, dklen=32, maxmem=0)
dk = hashlib.scrypt(pw, salt=salt, **params)
encoded = (
    f"scrypt${params['n']}${params['r']}${params['p']}$"
    f"{base64.b64encode(salt).decode()}${base64.b64encode(dk).decode()}"
)

# Re-derive from the encoded form exactly as the provider does on login.
scheme, n, r, p, salt_b64, dk_b64 = encoded.split("$")
check = hashlib.scrypt(
    pw, salt=base64.b64decode(salt_b64),
    n=int(n), r=int(r), p=int(p), dklen=len(base64.b64decode(dk_b64)), maxmem=0,
)
if scheme != "scrypt" or not hmac.compare_digest(check, base64.b64decode(dk_b64)):
    sys.exit("hash does not verify against the password it was derived from")
print(encoded)
PY
)"
unset pw pw_repeat

if [[ "$dry_run" == true ]]; then
  printf 'Dry run: hash generated and verified (%d chars, %d fields). Nothing written.\n' \
    "${#hash}" "$(awk -F'$' '{print NF}' <<<"$hash")"
  exit 0
fi

# sops set takes the value as JSON; the hash contains $ and / and must not be
# reinterpreted by the shell or the YAML writer.
json_encode() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

printf 'Writing %s ...\n' "$HASH_KEY"
sops set "$SECRETS" "[\"$HASH_KEY\"]" "$(json_encode "$hash")"

if [[ "$rotate_sessions" == true ]]; then
  printf 'Writing %s (all sessions will be signed out) ...\n' "$SECRET_KEY"
  sops set "$SECRETS" "[\"$SECRET_KEY\"]" "$(json_encode "$(openssl rand -base64 32)")"
fi

# Read back what landed in the file. A quoting regression would store the hash
# with literal quotes or a truncated field count, which the dashboard accepts
# at startup and only rejects at login time — too late to notice.
sops decrypt "$SECRETS" | HASH_KEY="$HASH_KEY" python3 - <<'PY'
import os, re, sys

key = os.environ["HASH_KEY"]
match = re.search(rf"^{key}: *(.*)$", sys.stdin.read(), re.M)
if not match:
    sys.exit(f"{key} is missing from the file after writing it")
value = match.group(1).strip()
if not re.fullmatch(r"scrypt\$16384\$8\$1\$[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+", value):
    sys.exit(f"{key} has an unexpected shape after writing ({len(value)} chars)")
print(f"Stored {key}: {len(value)} chars, shape verified.")
PY

message="ava: rotate dashboard password"
[[ "$rotate_sessions" == true ]] && message="$message and session secret"

git add "$SECRETS"
git commit -q -m "$message" \
  -m "Rotates the scrypt hash the bundled basic auth provider checks against."

if [[ "$push" == true ]]; then
  git push origin HEAD
  printf '\nPushed. flake-check runs first, then the GitOps controller redeploys hl01\n'
  printf 'and restartUnits brings the ava container back with the new hash.\n'
else
  printf '\nCommitted. Push to deploy:\n  git push origin main\n'
fi

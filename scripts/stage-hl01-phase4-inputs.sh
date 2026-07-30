#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

die() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  die "usage: $0 FINAL_EXPORT_DIRECTORY AGE_IDENTITY [TARGET]"
fi

readonly source_dir="$1"
readonly age_identity="$2"
readonly target="${3:-ecomex@10.20.50.11}"
readonly target_root="/home/ecomex/.local/share/nix-configs-migration/hl01"
readonly target_input="${target_root}/restore-input"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly encrypted_payloads=(
  immich-postgres.dump.age
  immich-upload.tar.zst.age
  paperless-postgres.dump.age
  paperless-data.tar.zst.age
  ava-home.tar.zst.age
  haushaltsbuch.sqlite.age
  honcho-postgres.dump.age
)

[[ -d "${source_dir}" ]] || die "missing final export directory"
[[ -f "${age_identity}" ]] || die "missing age identity"
[[ -f "${source_dir}/RESTORE-METADATA" ]] || die "missing restore metadata"
[[ -f "${source_dir}/SHA256SUMS" ]] || die "missing encrypted checksum manifest"
for payload in "${encrypted_payloads[@]}"; do
  [[ -f "${source_dir}/${payload}" ]] || die "missing encrypted payload: ${payload}"
done

echo "== Verifying encrypted final exports =="
(
  cd "${source_dir}"
  if command -v sha256sum >/dev/null; then
    sha256sum --check --strict SHA256SUMS
  else
    shasum -a 256 --check SHA256SUMS
  fi
)

ssh "${target}" "
  set -e
  test ! -e '${target_input}'
  install -d -m 700 '${target_root}' '${target_input}'
"

echo "== Decrypting directly into hl01 restore staging =="
for encrypted_name in "${encrypted_payloads[@]}"; do
  plain_name="${encrypted_name%.age}"
  age --decrypt --identity "${age_identity}" "${source_dir}/${encrypted_name}" |
    ssh "${target}" "
      set -e
      umask 077
      dd of='${target_input}/${plain_name}.partial' status=none
      mv '${target_input}/${plain_name}.partial' '${target_input}/${plain_name}'
    "
  echo "Staged ${plain_name}"
done

scp \
  "${source_dir}/RESTORE-METADATA" \
  "${target}:${target_input}/RESTORE-METADATA"
scp \
  "${script_dir}/restore-hl01-phase4.sh" \
  "${script_dir}/rollback-hl01-phase4.sh" \
  "${target}:${target_root}/"

ssh "${target}" "
  set -e
  cd '${target_input}'
  sha256sum \
    immich-postgres.dump \
    immich-upload.tar.zst \
    paperless-postgres.dump \
    paperless-data.tar.zst \
    ava-home.tar.zst \
    haushaltsbuch.sqlite \
    honcho-postgres.dump >SHA256SUMS
  chmod 600 SHA256SUMS RESTORE-METADATA
  chmod 700 \
    '${target_root}/restore-hl01-phase4.sh' \
    '${target_root}/rollback-hl01-phase4.sh'
"

echo
echo "All plaintext restore inputs are staged on ${target}."
echo "They remain mode 0600 and must be removed only after application acceptance."

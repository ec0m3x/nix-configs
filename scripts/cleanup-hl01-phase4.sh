#!/run/current-system/sw/bin/bash

set -Eeuo pipefail
umask 077
export PATH="/run/current-system/sw/bin:/run/wrappers/bin"

readonly complete_file="/srv/.hl01-phase4-restore-complete"
readonly restore_input_expected="/home/ecomex/.local/share/nix-configs-migration/hl01/restore-input"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

state_value() {
  local key="$1"
  local value

  value="$(sed -n "s/^${key}=//p" "${complete_file}" | head -n 1)"
  [[ -n "${value}" ]] || die "missing state value: ${key}"
  printf '%s' "${value}"
}

[[ "${EUID}" -eq 0 ]] || die "run this script as root"
[[ -f "${complete_file}" ]] || die "restore completion marker is missing"
[[ -z "$(sed -n 's/^cleaned=//p' "${complete_file}" | head -n 1)" ]] || \
  die "Phase 4 temporary data was already cleaned"

readonly immich_previous="$(state_value immich_previous)"
readonly paperless_data_previous="$(state_value paperless_data_previous)"
readonly paperless_media_previous="$(state_value paperless_media_previous)"
readonly paperless_consume_previous="$(state_value paperless_consume_previous)"
readonly ava_previous="$(state_value ava_previous)"
readonly haushaltsbuch_previous="$(state_value haushaltsbuch_previous)"
readonly restore_input="$(state_value restore_input)"

run_id="${immich_previous#/srv/immich/upload.pre-restore-}"
readonly run_id
[[ "${run_id}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "invalid restore run ID"

[[ "${immich_previous}" == "/srv/immich/upload.pre-restore-${run_id}" ]] || die "unexpected Immich path"
[[ "${paperless_data_previous}" == "/srv/paperless/data.pre-restore-${run_id}" ]] || die "unexpected Paperless data path"
[[ "${paperless_media_previous}" == "/srv/paperless/media.pre-restore-${run_id}" ]] || die "unexpected Paperless media path"
[[ "${paperless_consume_previous}" == "/srv/paperless/consume.pre-restore-${run_id}" ]] || die "unexpected Paperless consume path"
[[ "${ava_previous}" == "/home/hermes.pre-restore-${run_id}" ]] || die "unexpected AVA path"
[[ "${haushaltsbuch_previous}" == "/srv/haushaltsbuch.pre-restore-${run_id}" ]] || die "unexpected Haushaltsbuch path"
[[ "${restore_input}" == "${restore_input_expected}" ]] || die "unexpected restore input path"

for active_path in \
  /srv/immich/upload \
  /srv/paperless/data \
  /srv/paperless/media \
  /srv/paperless/consume \
  /home/hermes \
  /srv/haushaltsbuch; do
  [[ -d "${active_path}" ]] || die "active application path is missing: ${active_path}"
done

readonly cleanup_paths=(
  "${immich_previous}"
  "${paperless_data_previous}"
  "${paperless_media_previous}"
  "${paperless_consume_previous}"
  "${ava_previous}"
  "${haushaltsbuch_previous}"
  "${restore_input}"
)

echo "Removing accepted Phase 4 temporary data:"
printf '  %s\n' "${cleanup_paths[@]}"
rm --recursive --force -- "${cleanup_paths[@]}"

for cleanup_path in "${cleanup_paths[@]}"; do
  [[ ! -e "${cleanup_path}" && ! -L "${cleanup_path}" ]] || \
    die "cleanup target still exists: ${cleanup_path}"
done

readonly cleanup_time="$(date -u --iso-8601=seconds)"
printf \
  'accepted=%s\ncleaned=%s\ncleanup=plaintext-restore-input-and-pre-restore-targets\n' \
  "${cleanup_time}" \
  "${cleanup_time}" >>"${complete_file}"

echo "hl01 Phase 4 temporary data cleanup completed successfully."
echo "Encrypted external final exports were not touched."

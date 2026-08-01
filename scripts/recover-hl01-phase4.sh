#!/run/current-system/sw/bin/bash

set -Eeuo pipefail
umask 077
export PATH="/run/current-system/sw/bin:/run/wrappers/bin"

readonly restore_root="/home/ecomex/.local/share/nix-configs-migration/hl01"
readonly state_file="/srv/.hl01-phase4-restore-state"
readonly complete_file="/srv/.hl01-phase4-restore-complete"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run this script as root" >&2
  exit 1
fi

[[ -f "${state_file}" ]] || {
  echo "ERROR: no partial hl01 restore state exists" >&2
  exit 1
}
[[ ! -e "${complete_file}" ]] || {
  echo "ERROR: hl01 restore is already complete" >&2
  exit 1
}

"${restore_root}/rollback-hl01-phase4.sh"
exec "${restore_root}/restore-hl01-phase4.sh"

#!/run/current-system/sw/bin/bash

set -Eeuo pipefail
umask 077
export PATH="/run/current-system/sw/bin:/run/wrappers/bin"

readonly state_file="/srv/.hl01-phase4-restore-state"
readonly complete_file="/srv/.hl01-phase4-restore-complete"
readonly hermes_launcher="/home/hermes/.local/bin/hermes"
readonly restore_input="/home/ecomex/.local/share/nix-configs-migration/hl01/restore-input"
readonly app_units=(
  postgresql.service
  redis-immich.service
  redis-paperless.service
  redis-honcho.service
  immich-machine-learning.service
  immich-server.service
  paperless-web.service
  paperless-consumer.service
  paperless-task-queue.service
  paperless-scheduler.service
  hermes-dashboard.service
  podman-haushaltsbuch-web.service
  podman-haushaltsbuch-scheduler.service
  podman-honcho-api.service
  podman-honcho-deriver.service
  open-webui.service
)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

state_value() {
  local key="$1"
  local value

  value="$(sed -n "s/^${key}=//p" "${state_file}" | head -n 1)"
  [[ -n "${value}" ]] || die "missing state value: ${key}"
  printf '%s' "${value}"
}

wait_for_http() {
  local label="$1"
  local url="$2"

  for _attempt in $(seq 1 90); do
    if curl --fail --silent --show-error --max-time 5 "${url}" >/dev/null 2>&1; then
      echo "${label}: ready"
      return 0
    fi
    sleep 2
  done
  die "${label} did not become ready: ${url}"
}

[[ "${EUID}" -eq 0 ]] || die "run this script as root"
[[ -f "${state_file}" ]] || die "no partial hl01 restore state exists"
[[ ! -e "${complete_file}" ]] || die "hl01 restore is already complete"
[[ -x "${hermes_launcher}" ]] || die "Hermes launcher is missing"

run_id="$(state_value run_id)"
readonly run_id
[[ "${run_id}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "invalid restore run ID"

launcher_header="$(head -n 1 "${hermes_launcher}")"
if [[ "${launcher_header}" == "#!/usr/bin/env bash" ]]; then
  launcher_temp="$(mktemp)"
  readonly launcher_temp
  trap 'rm -f "${launcher_temp}"' EXIT
  {
    printf '#!/run/current-system/sw/bin/bash\n'
    tail -n +2 "${hermes_launcher}"
  } >"${launcher_temp}"
  install --owner=hermes --group=hermes --mode=0700 \
    "${launcher_temp}" "${hermes_launcher}"
elif [[ "${launcher_header}" != "#!/run/current-system/sw/bin/bash" ]]; then
  die "unexpected Hermes launcher header: ${launcher_header}"
fi

systemctl reset-failed hermes-dashboard.service
systemctl restart hermes-dashboard.service

wait_for_http "Immich" "http://10.20.50.11:2283/api/server/ping"
wait_for_http "Paperless" "http://10.20.50.11:8000/"
wait_for_http "AVA" "http://10.20.50.11:9119/"
wait_for_http "Haushaltsbuch" "http://10.20.50.11:8787/healthz"
wait_for_http "Honcho" "http://127.0.0.1:8010/health"
wait_for_http "Open WebUI" "http://10.20.50.11:8080/"
systemctl is-active "${app_units[@]}"

printf \
  'completed=%s\nimmich_previous=%s\npaperless_data_previous=%s\npaperless_media_previous=%s\npaperless_consume_previous=%s\nava_previous=%s\nhaushaltsbuch_previous=%s\nrestore_input=%s\n' \
  "$(date -u --iso-8601=seconds)" \
  "/srv/immich/upload.pre-restore-${run_id}" \
  "/srv/paperless/data.pre-restore-${run_id}" \
  "/srv/paperless/media.pre-restore-${run_id}" \
  "/srv/paperless/consume.pre-restore-${run_id}" \
  "/home/hermes.pre-restore-${run_id}" \
  "/srv/haushaltsbuch.pre-restore-${run_id}" \
  "${restore_input}" >>"${state_file}"
mv "${state_file}" "${complete_file}"

echo "hl01 Phase 4 restore finalized successfully."
echo "State: ${complete_file}"

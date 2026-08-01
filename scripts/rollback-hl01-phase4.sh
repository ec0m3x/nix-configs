#!/run/current-system/sw/bin/bash

set -Eeuo pipefail
umask 077
export PATH="/run/current-system/sw/bin:/run/wrappers/bin"

readonly state_file="/srv/.hl01-phase4-restore-state"
readonly complete_file="/srv/.hl01-phase4-restore-complete"
readonly app_units=(
  immich-server.service
  immich-machine-learning.service
  paperless-consumer.service
  paperless-scheduler.service
  paperless-task-queue.service
  paperless-web.service
  hermes-dashboard.service
  podman-haushaltsbuch-scheduler.service
  podman-haushaltsbuch-web.service
  podman-honcho-deriver.service
  podman-honcho-api.service
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

remove_exact_tree() {
  local path="$1"
  local allowed_prefix="$2"

  [[ "${path}" == "${allowed_prefix}"* ]] ||
    die "refusing to remove unexpected path: ${path}"
  [[ -e "${path}" ]] || return 0
  find "${path}" -depth -delete
}

restore_database() {
  local database="$1"
  local owner="$2"
  local dump="$3"

  [[ -f "${dump}" ]] || die "missing pre-restore database dump: ${dump}"
  runuser --user=postgres -- dropdb --if-exists --force "${database}"
  runuser --user=postgres -- createdb --owner="${owner}" "${database}"
  if [[ "${database}" == "immich" ]]; then
    for extension in cube earthdistance pg_trgm unaccent vector vchord; do
      runuser --user=postgres -- \
        psql \
        --dbname=immich \
        --set=ON_ERROR_STOP=1 \
        --command="CREATE EXTENSION IF NOT EXISTS \"${extension}\""
    done
    runuser --user=postgres -- \
      psql \
      --dbname=immich \
      --set=ON_ERROR_STOP=1 \
      --command='CREATE EXTENSION IF NOT EXISTS "uuid-ossp"'
  elif [[ "${database}" == "honcho" ]]; then
    runuser --user=postgres -- \
      psql \
      --dbname=honcho \
      --set=ON_ERROR_STOP=1 \
      --command='CREATE EXTENSION IF NOT EXISTS vector'
  fi
  runuser --user=postgres -- \
    pg_restore \
    --exit-on-error \
    --no-owner \
    --no-privileges \
    --no-comments \
    --role="${owner}" \
    --dbname="${database}" \
    "${dump}"
}

if [[ "${EUID}" -ne 0 ]]; then
  die "run this script as root"
fi

[[ -f "${state_file}" ]] || die "no partial hl01 restore state exists"
[[ ! -e "${complete_file}" ]] ||
  die "restore is complete; rollback requires a separate acceptance decision"

run_id="$(state_value run_id)"
readonly run_id
[[ "${run_id}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "invalid restore run ID"
postgres_backup_dir="$(state_value postgres_backup_dir)"
readonly postgres_backup_dir
readonly immich_previous="/srv/immich/upload.pre-restore-${run_id}"
readonly paperless_data_previous="/srv/paperless/data.pre-restore-${run_id}"
readonly paperless_media_previous="/srv/paperless/media.pre-restore-${run_id}"
readonly paperless_consume_previous="/srv/paperless/consume.pre-restore-${run_id}"
readonly ava_previous="/home/hermes.pre-restore-${run_id}"
readonly haushaltsbuch_previous="/srv/haushaltsbuch.pre-restore-${run_id}"
log_file="/var/log/hl01-phase4-rollback-$(date -u +%Y%m%dT%H%M%SZ).log"
readonly log_file

exec > >(tee -a "${log_file}") 2>&1

echo "== Rolling back partial hl01 Phase 4 restore =="
systemctl stop "${app_units[@]}"

if mountpoint --quiet /opt/immich/upload; then
  umount /opt/immich/upload
fi
if [[ -d "${immich_previous}" ]]; then
  remove_exact_tree /srv/immich/upload "/srv/immich/upload"
  mv "${immich_previous}" /srv/immich/upload
fi
mount /opt/immich/upload

if [[ -d "${paperless_data_previous}" ]]; then
  remove_exact_tree /srv/paperless/data "/srv/paperless/data"
  mv "${paperless_data_previous}" /srv/paperless/data
fi
if [[ -d "${paperless_media_previous}" ]]; then
  remove_exact_tree /srv/paperless/media "/srv/paperless/media"
  mv "${paperless_media_previous}" /srv/paperless/media
fi
if [[ -d "${paperless_consume_previous}" ]]; then
  remove_exact_tree /srv/paperless/consume "/srv/paperless/consume"
  mv "${paperless_consume_previous}" /srv/paperless/consume
fi

if [[ -d "${ava_previous}" ]]; then
  remove_exact_tree /home/hermes "/home/hermes"
  mv "${ava_previous}" /home/hermes
fi

if [[ -d "${haushaltsbuch_previous}" ]]; then
  remove_exact_tree /srv/haushaltsbuch "/srv/haushaltsbuch"
  mv "${haushaltsbuch_previous}" /srv/haushaltsbuch
fi

restore_database immich immich "${postgres_backup_dir}/immich.dump"
restore_database paperless paperless "${postgres_backup_dir}/paperless.dump"
restore_database honcho honcho "${postgres_backup_dir}/honcho.dump"
systemctl restart honcho-postgresql-provision.service

systemctl start \
  immich-machine-learning.service \
  immich-server.service \
  paperless-web.service \
  paperless-consumer.service \
  paperless-task-queue.service \
  paperless-scheduler.service \
  podman-haushaltsbuch-web.service \
  podman-haushaltsbuch-scheduler.service \
  podman-honcho-api.service \
  podman-honcho-deriver.service
systemctl start hermes-dashboard.service || true

mv "${state_file}" "${state_file}.rolled-back-${run_id}"

echo
echo "Partial restore rolled back to the fresh target state."
echo "Log: ${log_file}"

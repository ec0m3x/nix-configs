#!/run/current-system/sw/bin/bash

set -Eeuo pipefail
umask 077
export PATH="/run/current-system/sw/bin:/run/wrappers/bin"

readonly restore_input="/home/ecomex/.local/share/nix-configs-migration/hl01/restore-input"
readonly metadata_file="${restore_input}/RESTORE-METADATA"
readonly checksums_file="${restore_input}/SHA256SUMS"
readonly immich_dump="${restore_input}/immich-postgres.dump"
readonly immich_archive="${restore_input}/immich-upload.tar.zst"
readonly paperless_dump="${restore_input}/paperless-postgres.dump"
readonly paperless_archive="${restore_input}/paperless-data.tar.zst"
readonly ava_archive="${restore_input}/ava-home.tar.zst"
readonly haushaltsbuch_database="${restore_input}/haushaltsbuch.sqlite"
readonly honcho_dump="${restore_input}/honcho-postgres.dump"
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

assert_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    die "${label}: expected ${expected}, got ${actual}"
  fi
  echo "${label}: ${actual}"
}

metadata_value() {
  local key="$1"
  local pattern="$2"
  local value

  value="$(sed -n "s/^${key}=//p" "${metadata_file}")"
  [[ -n "${value}" ]] || die "missing metadata value: ${key}"
  [[ "$(grep -c "^${key}=" "${metadata_file}")" -eq 1 ]] ||
    die "metadata value is not unique: ${key}"
  [[ "${value}" =~ ${pattern} ]] || die "invalid metadata value: ${key}"
  printf '%s' "${value}"
}

postgres_scalar() {
  local database="$1"
  local query="$2"

  runuser --user=postgres -- \
    psql \
    --no-psqlrc \
    --tuples-only \
    --no-align \
    --dbname="${database}" \
    --command="${query}"
}

recreate_database() {
  local database="$1"
  local owner="$2"

  runuser --user=postgres -- dropdb --if-exists --force "${database}"
  runuser --user=postgres -- createdb --owner="${owner}" "${database}"
}

wait_for_http() {
  local label="$1"
  local url="$2"
  local response=""

  for _attempt in $(seq 1 90); do
    if response="$(curl --fail --silent --show-error --max-time 5 "${url}" 2>/dev/null)"; then
      echo "${label}: ready"
      printf '%s' "${response}"
      return 0
    fi
    sleep 2
  done
  die "${label} did not become ready: ${url}"
}

check_immich_paths() {
  local label="$1"
  local query="$2"
  local total=0
  local missing=0
  local path

  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    total=$((total + 1))
    [[ -e "${path}" ]] || missing=$((missing + 1))
  done < <(postgres_scalar immich "${query}")

  echo "${label} references: ${total}"
  assert_equal "${label} missing" "${missing}" "0"
}

if [[ "${EUID}" -ne 0 ]]; then
  die "run this script as root"
fi

run_id="${HL01_RESTORE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
readonly run_id
[[ "${run_id}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "invalid restore run ID"
readonly log_file="/var/log/hl01-phase4-restore-${run_id}.log"
readonly immich_incoming="/srv/immich/upload.restore-incoming-${run_id}"
readonly immich_previous="/srv/immich/upload.pre-restore-${run_id}"
readonly paperless_source="/srv/paperless/source.restore-${run_id}"
readonly paperless_data_previous="/srv/paperless/data.pre-restore-${run_id}"
readonly paperless_media_previous="/srv/paperless/media.pre-restore-${run_id}"
readonly paperless_consume_previous="/srv/paperless/consume.pre-restore-${run_id}"
readonly ava_incoming="/home/hermes.restore-incoming-${run_id}"
readonly ava_previous="/home/hermes.pre-restore-${run_id}"
readonly haushaltsbuch_previous="/srv/haushaltsbuch.pre-restore-${run_id}"
readonly postgres_backup_dir="/srv/postgresql/pre-phase4-${run_id}"

exec > >(tee -a "${log_file}") 2>&1

on_error() {
  local exit_code=$?

  echo
  echo "Restore failed with exit code ${exit_code}."
  if [[ -e "${state_file}" ]]; then
    printf 'failed=%s\nlog=%s\n' \
      "$(date -u --iso-8601=seconds)" \
      "${log_file}" >>"${state_file}"
    echo "Application services remain stopped after a partial restore."
    echo "Inspect ${log_file} and ${state_file}; use rollback-hl01-phase4.sh if required."
  else
    echo "The failure occurred during preflight; no target service was stopped."
  fi
  exit "${exit_code}"
}
trap on_error ERR

echo "== hl01 Phase 4 restore preflight =="
[[ ! -e "${state_file}" ]] || die "restore state already exists: ${state_file}"
[[ ! -e "${complete_file}" ]] || die "restore was already completed: ${complete_file}"
[[ -f "${metadata_file}" ]] || die "missing restore metadata"
[[ -f "${checksums_file}" ]] || die "missing plaintext checksum manifest"

expected_immich_files="$(metadata_value immich_files '^[0-9]+$')"
expected_immich_assets="$(metadata_value immich_assets '^[0-9]+$')"
expected_immich_users="$(metadata_value immich_users '^[0-9]+$')"
expected_paperless_export_files="$(metadata_value paperless_export_files '^[0-9]+$')"
expected_paperless_documents="$(metadata_value paperless_documents '^[0-9]+$')"
expected_paperless_users="$(metadata_value paperless_users '^[0-9]+$')"
expected_paperless_media_files="$(metadata_value paperless_media_files '^[0-9]+$')"
expected_ava_entries="$(metadata_value ava_entries '^[0-9]+$')"
expected_ava_commit="$(metadata_value ava_commit '^[0-9a-f]{40}$')"
expected_haushaltsbuch_tables="$(metadata_value haushaltsbuch_tables '^[0-9]+$')"
expected_honcho_tables="$(metadata_value honcho_tables '^[0-9]+$')"
readonly \
  expected_immich_files \
  expected_immich_assets \
  expected_immich_users \
  expected_paperless_export_files \
  expected_paperless_documents \
  expected_paperless_users \
  expected_paperless_media_files \
  expected_ava_entries \
  expected_ava_commit \
  expected_haushaltsbuch_tables \
  expected_honcho_tables

for input in \
  "${immich_dump}" \
  "${immich_archive}" \
  "${paperless_dump}" \
  "${paperless_archive}" \
  "${ava_archive}" \
  "${haushaltsbuch_database}" \
  "${honcho_dump}"; do
  [[ -f "${input}" ]] || die "missing restore input: ${input}"
done

(
  cd "${restore_input}"
  sha256sum --check --strict SHA256SUMS
)
pg_restore --list "${immich_dump}" >/dev/null
pg_restore --list "${paperless_dump}" >/dev/null
pg_restore --list "${honcho_dump}" >/dev/null
zstd --test "${immich_archive}"
zstd --test "${paperless_archive}"
ava_archive_entries="$(
  zstd --decompress --stdout "${ava_archive}" |
    tar --list --file=- |
    awk '
      NR == 1 && $0 != "home/hermes/" { exit 1 }
      { count++ }
      END { print count }
    '
)"
[[ "${ava_archive_entries}" =~ ^[0-9]+$ ]] || die "invalid AVA archive inventory"
((ava_archive_entries >= 1)) || die "empty AVA archive"
readonly ava_archive_entries
assert_equal \
  "Haushaltsbuch SQLite quick_check" \
  "$(sqlite3 "${haushaltsbuch_database}" 'PRAGMA quick_check;')" \
  "ok"
assert_equal \
  "Haushaltsbuch tables" \
  "$(sqlite3 "${haushaltsbuch_database}" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")" \
  "${expected_haushaltsbuch_tables}"

mountpoint --quiet /srv || die "/srv is not mounted"
mountpoint --quiet /opt/immich/upload ||
  die "/opt/immich/upload is not the declared bind mount"
systemctl is-active --quiet postgresql.service || die "PostgreSQL is not active"
systemctl is-active --quiet redis-immich.service || die "Immich Redis is not active"
systemctl is-active --quiet redis-paperless.service || die "Paperless Redis is not active"
systemctl is-active --quiet redis-honcho.service || die "Honcho Redis is not active"
command -v paperless-manage >/dev/null || die "paperless-manage is not installed"

srv_available="$(df --block-size=1 --output=avail /srv | tail -n 1 | tr -d ' ')"
[[ "${srv_available}" =~ ^[0-9]+$ ]] || die "could not determine free space on /srv"
((srv_available >= 40 * 1024 * 1024 * 1024)) ||
  die "less than 40 GiB is available on /srv"

echo "== Preparing application data =="
if [[ -d "${immich_incoming}" ]]; then
  echo "Reusing existing Immich incoming directory: ${immich_incoming}"
elif [[ -e "${immich_incoming}" ]]; then
  die "Immich incoming path is not a directory"
else
  install --directory --owner=immich --group=immich --mode=0700 "${immich_incoming}"
  zstd --decompress --stdout "${immich_archive}" |
    tar --extract \
      --file=- \
      --directory="${immich_incoming}" \
      --strip-components=3 \
      opt/immich/upload
  chown --recursive immich:immich "${immich_incoming}"
fi
assert_equal \
  "Immich media files" \
  "$(find "${immich_incoming}" -type f -printf '.' | wc -c)" \
  "${expected_immich_files}"

if [[ -d "${paperless_source}" ]]; then
  echo "Reusing existing Paperless staging directory: ${paperless_source}"
elif [[ -e "${paperless_source}" ]]; then
  die "Paperless staging path is not a directory"
else
  install --directory --owner=paperless --group=paperless --mode=0700 "${paperless_source}"
  zstd --decompress --stdout "${paperless_archive}" |
    tar --extract --file=- --directory="${paperless_source}" opt/paperless_data
  chown --recursive paperless:paperless "${paperless_source}"
fi
mapfile -d '' paperless_exports < <(
  find \
    "${paperless_source}/opt/paperless_data" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -name 'export-*' \
    -print0
)
[[ "${#paperless_exports[@]}" -eq 1 ]] ||
  die "expected exactly one Paperless exporter directory"
readonly paperless_export="${paperless_exports[0]}"
assert_equal \
  "Paperless exporter files" \
  "$(find "${paperless_export}" -type f -printf '.' | wc -c)" \
  "${expected_paperless_export_files}"

if [[ -d "${ava_incoming}" ]]; then
  echo "Reusing existing AVA incoming directory: ${ava_incoming}"
elif [[ -e "${ava_incoming}" ]]; then
  die "AVA incoming path is not a directory"
else
  install --directory --owner=hermes --group=hermes --mode=0700 "${ava_incoming}"
  zstd --decompress --stdout "${ava_archive}" |
    tar --extract \
      --file=- \
      --directory="${ava_incoming}" \
      --strip-components=2 \
      home/hermes
  chown --recursive hermes:hermes "${ava_incoming}"
fi
actual_ava_entries="$(find "${ava_incoming}" -mindepth 1 -printf '.' | wc -c)"
readonly actual_ava_entries
assert_equal \
  "AVA archived entries" \
  "${actual_ava_entries}" \
  "$((ava_archive_entries - 1))"
((expected_ava_entries >= actual_ava_entries)) ||
  die "AVA archive contains more entries than the source inventory"
echo "AVA source-only entries omitted from tar: $((expected_ava_entries - actual_ava_entries))"
assert_equal \
  "AVA checkout" \
  "$(runuser --user=hermes -- git -C "${ava_incoming}/.hermes/hermes-agent" rev-parse HEAD)" \
  "${expected_ava_commit}"
assert_equal \
  "AVA SQLite quick_check" \
  "$(sqlite3 "${ava_incoming}/.hermes/state.db" 'PRAGMA quick_check;')" \
  "ok"
[[ -x "${ava_incoming}/.local/bin/hermes" ]] || die "restored Hermes launcher is not executable"

echo "== Entering target maintenance window =="
install --directory --owner=postgres --group=postgres --mode=0700 "${postgres_backup_dir}"
runuser --user=postgres -- pg_dump --format=custom immich \
  >"${postgres_backup_dir}/immich.dump"
runuser --user=postgres -- pg_dump --format=custom paperless \
  >"${postgres_backup_dir}/paperless.dump"
runuser --user=postgres -- pg_dump --format=custom honcho \
  >"${postgres_backup_dir}/honcho.dump"
chown postgres:postgres "${postgres_backup_dir}"/*.dump

printf \
  'started=%s\nrun_id=%s\nlog=%s\npostgres_backup_dir=%s\n' \
  "$(date -u --iso-8601=seconds)" \
  "${run_id}" \
  "${log_file}" \
  "${postgres_backup_dir}" >"${state_file}"

systemctl stop "${app_units[@]}"

umount /opt/immich/upload
mv /srv/immich/upload "${immich_previous}"
mv "${immich_incoming}" /srv/immich/upload
mount /opt/immich/upload

mv /srv/paperless/data "${paperless_data_previous}"
mv /srv/paperless/media "${paperless_media_previous}"
mv /srv/paperless/consume "${paperless_consume_previous}"
install --directory --owner=paperless --group=paperless --mode=0700 \
  /srv/paperless/data \
  /srv/paperless/media \
  /srv/paperless/consume

mv /home/hermes "${ava_previous}"
mv "${ava_incoming}" /home/hermes
chown --recursive hermes:hermes /home/hermes

mv /srv/haushaltsbuch "${haushaltsbuch_previous}"
install --directory --owner=10001 --group=10001 --mode=0750 /srv/haushaltsbuch
install \
  --owner=10001 \
  --group=10001 \
  --mode=0600 \
  "${haushaltsbuch_database}" \
  /srv/haushaltsbuch/haushaltsbuch.db

echo "== Restoring Immich =="
recreate_database immich immich
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
runuser --user=postgres -- \
  pg_restore \
  --exit-on-error \
  --no-owner \
  --no-privileges \
  --no-comments \
  --role=immich \
  --dbname=immich <"${immich_dump}"
runuser --user=postgres -- \
  psql \
  --dbname=immich \
  --set=ON_ERROR_STOP=1 \
  --command="
    UPDATE system_metadata
    SET value = jsonb_set(
      value,
      '{machineLearning,urls}',
      '[\"http://127.0.0.1:3003\"]'::jsonb,
      true
    )
    WHERE key = 'system-config';
  "
assert_equal \
  "Immich assets" \
  "$(postgres_scalar immich 'SELECT COUNT(*) FROM asset;')" \
  "${expected_immich_assets}"
assert_equal \
  "Immich users" \
  "$(postgres_scalar immich 'SELECT COUNT(*) FROM "user";')" \
  "${expected_immich_users}"
assert_equal \
  "Immich machine-learning URL" \
  "$(postgres_scalar immich "SELECT value #>> '{machineLearning,urls,0}' FROM system_metadata WHERE key = 'system-config';")" \
  "http://127.0.0.1:3003"
check_immich_paths \
  "Immich originals" \
  'SELECT "originalPath" FROM asset WHERE "originalPath" IS NOT NULL;'
check_immich_paths \
  "Immich derivatives" \
  'SELECT path FROM asset_file WHERE path IS NOT NULL;'
check_immich_paths \
  "Immich person thumbnails" \
  'SELECT "thumbnailPath" FROM person WHERE "thumbnailPath" IS NOT NULL;'
check_immich_paths \
  "Immich profile images" \
  'SELECT "profileImagePath" FROM "user" WHERE "profileImagePath" IS NOT NULL;'

echo "== Importing Paperless =="
recreate_database paperless paperless
paperless-manage migrate --noinput
paperless-manage document_importer "${paperless_export}"
paperless-manage document_sanity_checker
assert_equal \
  "Paperless documents" \
  "$(postgres_scalar paperless 'SELECT COUNT(*) FROM documents_document;')" \
  "${expected_paperless_documents}"
assert_equal \
  "Paperless users" \
  "$(postgres_scalar paperless 'SELECT COUNT(*) FROM auth_user;')" \
  "${expected_paperless_users}"
assert_equal \
  "Paperless media files" \
  "$(find /srv/paperless/media -type f -printf '.' | wc -c)" \
  "${expected_paperless_media_files}"

echo "== Restoring Honcho =="
recreate_database honcho honcho
runuser --user=postgres -- \
  psql \
  --dbname=honcho \
  --set=ON_ERROR_STOP=1 \
  --command='CREATE EXTENSION IF NOT EXISTS vector'
runuser --user=postgres -- \
  pg_restore \
  --exit-on-error \
  --no-owner \
  --no-privileges \
  --no-comments \
  --role=honcho \
  --dbname=honcho <"${honcho_dump}"
assert_equal \
  "Honcho tables" \
  "$(postgres_scalar honcho "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public';")" \
  "${expected_honcho_tables}"
systemctl restart honcho-postgresql-provision.service

echo "== Starting declared services =="
systemctl start \
  immich-machine-learning.service \
  immich-server.service \
  paperless-web.service \
  paperless-consumer.service \
  paperless-task-queue.service \
  paperless-scheduler.service \
  hermes-dashboard.service \
  podman-haushaltsbuch-web.service \
  podman-haushaltsbuch-scheduler.service \
  podman-honcho-api.service \
  podman-honcho-deriver.service

echo "== Health checks =="
immich_health="$(wait_for_http "Immich" "http://10.20.50.11:2283/api/server/ping")"
grep --quiet '"pong"' <<<"${immich_health}" || die "unexpected Immich ping response"
wait_for_http "Paperless" "http://10.20.50.11:8000/" >/dev/null
wait_for_http "AVA" "http://10.20.50.11:9119/" >/dev/null
wait_for_http "Haushaltsbuch" "http://10.20.50.11:8787/healthz" >/dev/null
wait_for_http "Honcho" "http://127.0.0.1:8010/health" >/dev/null
wait_for_http "Open WebUI" "http://10.20.50.11:8080/" >/dev/null

systemctl is-active \
  postgresql.service \
  redis-immich.service \
  redis-paperless.service \
  redis-honcho.service \
  immich-machine-learning.service \
  immich-server.service \
  paperless-web.service \
  paperless-consumer.service \
  paperless-task-queue.service \
  paperless-scheduler.service \
  hermes-dashboard.service \
  podman-haushaltsbuch-web.service \
  podman-haushaltsbuch-scheduler.service \
  podman-honcho-api.service \
  podman-honcho-deriver.service \
  open-webui.service

printf \
  'completed=%s\nimmich_previous=%s\npaperless_data_previous=%s\npaperless_media_previous=%s\npaperless_consume_previous=%s\nava_previous=%s\nhaushaltsbuch_previous=%s\nrestore_input=%s\n' \
  "$(date -u --iso-8601=seconds)" \
  "${immich_previous}" \
  "${paperless_data_previous}" \
  "${paperless_media_previous}" \
  "${paperless_consume_previous}" \
  "${ava_previous}" \
  "${haushaltsbuch_previous}" \
  "${restore_input}" >>"${state_file}"
mv "${state_file}" "${complete_file}"
trap - ERR

echo
echo "hl01 Phase 4 restore completed successfully."
echo "Pre-restore target data and plaintext restore input are retained until acceptance."
echo "State: ${complete_file}"
echo "Log: ${log_file}"

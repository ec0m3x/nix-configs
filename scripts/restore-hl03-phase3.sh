#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly restore_input="/home/ecomex/.local/share/nix-configs-migration/hl03/restore-input"
readonly nextcloud_source="${restore_input}/var/www/nextcloud-data"
readonly nextcloud_dump="${restore_input}/root/nextcloud-final-20260730-213541/nextcloud.sql.zst"
readonly litellm_dump="${restore_input}/litellm-postgres.dump"
readonly nextcloud_dump_sha256="3212f247b38f7793a724e7d570f4ee2c5910ca8ada24ecd762c1959a5bee664f"
readonly litellm_dump_sha256="a6d516fd8384ab5c52f9ac35f2a3b7e23c204337eb4b221d063c5615a4429d79"
readonly backup_uuid="bea9cd03-b112-4d84-8c7d-26d53635a9d7"
readonly expected_nextcloud_files="26290"
readonly expected_nextcloud_tables="144"
readonly expected_nextcloud_users="2"
readonly expected_litellm_tables="68"
readonly expected_litellm_models="17"
readonly expected_litellm_keys="45"
readonly expected_litellm_users="2"
readonly expected_litellm_migrations="320"

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

mysql_scalar() {
  mariadb --batch --skip-column-names --database=nextcloud --execute="$1"
}

postgres_scalar() {
  runuser --user=postgres -- \
    psql --no-psqlrc --tuples-only --no-align --dbname=litellm --command="$1"
}

if [[ "${EUID}" -ne 0 ]]; then
  die "run this script as root"
fi

readonly run_id="$(date -u +%Y%m%dT%H%M%SZ)"
readonly state_file="/srv/.hl03-phase3-restore-state"
readonly complete_file="/srv/.hl03-phase3-restore-complete"
readonly incoming_data="/srv/nextcloud/data.restore-incoming-${run_id}"
readonly previous_data="/srv/nextcloud/data.pre-restore-${run_id}"
readonly postgres_litellm_dump="/srv/postgresql/litellm-restore-${run_id}.dump"
readonly log_file="/var/log/hl03-phase3-restore-${run_id}.log"

exec > >(tee -a "${log_file}") 2>&1

on_error() {
  local exit_code=$?

  echo
  echo "Restore failed with exit code ${exit_code}."
  if [[ -e "${state_file}" ]]; then
    printf 'failed=%s\nlog=%s\n' "$(date -u --iso-8601=seconds)" "${log_file}" >>"${state_file}"
  fi
  echo "Services are intentionally not restarted automatically after a partial restore."
  echo "Inspect ${log_file} and ${state_file} before taking further action."
  exit "${exit_code}"
}
trap on_error ERR

echo "== hl03 Phase 3 restore preflight =="
[[ ! -e "${state_file}" ]] || die "restore state already exists: ${state_file}"
[[ ! -e "${complete_file}" ]] || die "restore was already completed: ${complete_file}"
[[ -d "${nextcloud_source}" ]] || die "missing Nextcloud data: ${nextcloud_source}"
[[ -f "${nextcloud_dump}" ]] || die "missing Nextcloud dump: ${nextcloud_dump}"
[[ -f "${litellm_dump}" ]] || die "missing LiteLLM dump: ${litellm_dump}"
[[ -s /srv/nextcloud/config/config.php ]] || die "missing target Nextcloud config.php"
[[ -d /srv/nextcloud/data ]] || die "missing target Nextcloud data directory"
[[ ! -e "${incoming_data}" ]] || die "incoming data path already exists"
[[ ! -e "${previous_data}" ]] || die "previous data path already exists"
[[ ! -e "${postgres_litellm_dump}" ]] || die "PostgreSQL restore dump already exists"

mountpoint --quiet /srv || die "/srv is not mounted"
mountpoint --quiet /srv/backup || die "/srv/backup is not mounted"
assert_equal \
  "EXCERIA filesystem UUID" \
  "$(findmnt --noheadings --output UUID --target /srv/backup)" \
  "${backup_uuid}"

systemctl is-active --quiet mysql.service || die "MariaDB is not active"
systemctl is-active --quiet postgresql.service || die "PostgreSQL is not active"
systemctl is-active --quiet cloudflared-token-tunnel.service || die "cloudflared is not active"
systemctl is-active --quiet restic-rest-server.service || die "restic-rest-server is not active"
systemctl is-active --quiet tailscaled.service || die "Tailscale is not active"

printf '%s  %s\n' "${nextcloud_dump_sha256}" "${nextcloud_dump}" | sha256sum --check -
printf '%s  %s\n' "${litellm_dump_sha256}" "${litellm_dump}" | sha256sum --check -
zstd --test "${nextcloud_dump}"
pg_restore --list "${litellm_dump}" >/dev/null

readonly source_file_count="$(find "${nextcloud_source}" -type f -printf '.' | wc -c)"
assert_equal "Nextcloud source files" "${source_file_count}" "${expected_nextcloud_files}"

nextcloud-occ status
curl --fail --silent --show-error --max-time 10 \
  --header "Host: cloud.sk4i.com" \
  http://10.20.50.13/status.php
echo
curl --fail --silent --show-error --max-time 10 \
  http://127.0.0.1:4000/health/readiness
echo

echo "== Preparing Nextcloud data on /srv =="
install --directory --owner=nextcloud --group=nextcloud --mode=0750 "${incoming_data}"
cp --archive --reflink=auto "${nextcloud_source}/." "${incoming_data}/"
chown --recursive nextcloud:nextcloud "${incoming_data}"
readonly incoming_file_count="$(find "${incoming_data}" -type f -printf '.' | wc -c)"
assert_equal "Copied Nextcloud files" "${incoming_file_count}" "${expected_nextcloud_files}"
sync --file-system "${incoming_data}"

install \
  --owner=postgres \
  --group=postgres \
  --mode=0400 \
  "${litellm_dump}" \
  "${postgres_litellm_dump}"
runuser --user=postgres -- pg_restore --list "${postgres_litellm_dump}" >/dev/null

printf 'started=%s\nrun_id=%s\nlog=%s\n' \
  "$(date -u --iso-8601=seconds)" \
  "${run_id}" \
  "${log_file}" >"${state_file}"

echo "== Entering maintenance window =="
nextcloud-occ maintenance:mode --on
systemctl stop nextcloud-cron.timer nextcloud-cron.service
systemctl stop nginx.service phpfpm-nextcloud.service
systemctl stop podman-litellm.service

echo "== Restoring Nextcloud =="
mv /srv/nextcloud/data "${previous_data}"
mv "${incoming_data}" /srv/nextcloud/data
chown --recursive nextcloud:nextcloud /srv/nextcloud/data

mariadb --execute="
  DROP DATABASE IF EXISTS nextcloud;
  CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
"
zstd --decompress --stdout "${nextcloud_dump}" |
  mariadb --database=nextcloud

assert_equal \
  "Nextcloud tables" \
  "$(mysql_scalar "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'nextcloud';")" \
  "${expected_nextcloud_tables}"
assert_equal \
  "Nextcloud users" \
  "$(mysql_scalar 'SELECT COUNT(*) FROM oc_users;')" \
  "${expected_nextcloud_users}"

echo "== Restoring LiteLLM =="
runuser --user=postgres -- dropdb --if-exists --force litellm
runuser --user=postgres -- createdb --owner=litellm litellm
runuser --user=postgres -- \
  pg_restore \
  --exit-on-error \
  --no-owner \
  --role=litellm \
  --dbname=litellm \
  "${postgres_litellm_dump}"

assert_equal \
  "LiteLLM physical tables" \
  "$(postgres_scalar "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';")" \
  "${expected_litellm_tables}"
assert_equal \
  "LiteLLM models" \
  "$(postgres_scalar 'SELECT COUNT(*) FROM "LiteLLM_ProxyModelTable";')" \
  "${expected_litellm_models}"
assert_equal \
  "LiteLLM virtual keys" \
  "$(postgres_scalar 'SELECT COUNT(*) FROM "LiteLLM_VerificationToken";')" \
  "${expected_litellm_keys}"
assert_equal \
  "LiteLLM users" \
  "$(postgres_scalar 'SELECT COUNT(*) FROM "LiteLLM_UserTable";')" \
  "${expected_litellm_users}"
assert_equal \
  "LiteLLM migrations" \
  "$(postgres_scalar 'SELECT COUNT(*) FROM "_prisma_migrations";')" \
  "${expected_litellm_migrations}"

echo "== Reconciling declared services =="
systemctl restart litellm-postgresql-provision.service
nextcloud-occ maintenance:mode --off
systemctl restart nextcloud-setup.service
nextcloud-occ maintenance:repair
nextcloud-occ db:add-missing-columns
nextcloud-occ db:add-missing-indices
nextcloud-occ db:add-missing-primary-keys

systemctl start phpfpm-nextcloud.service nginx.service nextcloud-cron.timer
systemctl start podman-litellm.service

echo "== Health checks =="
nextcloud-occ status
curl --fail --silent --show-error --max-time 10 \
  --header "Host: cloud.sk4i.com" \
  http://10.20.50.13/status.php
echo

litellm_health=""
for _attempt in $(seq 1 60); do
  if litellm_health="$(
    curl --fail --silent --show-error --max-time 5 \
      http://127.0.0.1:4000/health/readiness 2>/dev/null
  )"; then
    break
  fi
  sleep 2
done
[[ -n "${litellm_health}" ]] || die "LiteLLM did not become ready"
echo "${litellm_health}"

systemctl is-active \
  mysql.service \
  postgresql.service \
  redis-nextcloud.service \
  phpfpm-nextcloud.service \
  nginx.service \
  podman-litellm.service \
  cloudflared-token-tunnel.service \
  restic-rest-server.service \
  tailscaled.service

rm --force -- "${postgres_litellm_dump}"
printf 'completed=%s\nprevious_data=%s\nstaging=%s\n' \
  "$(date -u --iso-8601=seconds)" \
  "${previous_data}" \
  "${restore_input}" >>"${state_file}"
mv "${state_file}" "${complete_file}"
trap - ERR

echo
echo "Restore completed successfully."
echo "Previous fresh Nextcloud data retained at: ${previous_data}"
echo "Restore input retained at: ${restore_input}"
echo "Log: ${log_file}"

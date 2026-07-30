#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly restore_input="/home/ecomex/.local/share/nix-configs-migration/hl03/restore-input"
readonly litellm_dump="${restore_input}/litellm-postgres.dump"
readonly litellm_dump_sha256="a6d516fd8384ab5c52f9ac35f2a3b7e23c204337eb4b221d063c5615a4429d79"
readonly expected_nextcloud_files="26290"
readonly expected_nextcloud_tables="144"
readonly expected_nextcloud_users="2"
readonly expected_litellm_tables="68"
readonly expected_litellm_models="17"
readonly expected_litellm_keys="45"
readonly expected_litellm_users="2"
readonly expected_litellm_migrations="320"
readonly state_file="/srv/.hl03-phase3-restore-state"
readonly complete_file="/srv/.hl03-phase3-restore-complete"
readonly postgres_litellm_dump="/srv/postgresql/litellm-restore-resume.dump"
readonly log_file="/var/log/hl03-phase3-restore-resume-$(date -u +%Y%m%dT%H%M%SZ).log"

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

exec > >(tee -a "${log_file}") 2>&1

on_error() {
  local exit_code=$?

  echo
  echo "Resume failed with exit code ${exit_code}."
  printf 'resume_failed=%s\nresume_log=%s\n' \
    "$(date -u --iso-8601=seconds)" \
    "${log_file}" >>"${state_file}"
  echo "Services remain stopped. Inspect ${log_file} before continuing."
  exit "${exit_code}"
}
trap on_error ERR

echo "== hl03 Phase 3 restore resume preflight =="
[[ -f "${state_file}" ]] || die "missing partial-restore state: ${state_file}"
[[ ! -e "${complete_file}" ]] || die "restore is already complete"
[[ -f "${litellm_dump}" ]] || die "missing LiteLLM dump"
[[ -s /srv/nextcloud/config/config.php ]] || die "missing Nextcloud config.php"
[[ -d /srv/nextcloud/data ]] || die "missing restored Nextcloud data"

readonly run_id="$(sed -n 's/^run_id=//p' "${state_file}")"
[[ "${run_id}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "invalid run_id in restore state"
readonly previous_data="/srv/nextcloud/data.pre-restore-${run_id}"
[[ -d "${previous_data}" ]] || die "missing preserved pre-restore data"

systemctl is-active --quiet mysql.service || die "MariaDB is not active"
systemctl is-active --quiet postgresql.service || die "PostgreSQL is not active"
systemctl is-active --quiet nginx.service && die "nginx should still be stopped"
systemctl is-active --quiet phpfpm-nextcloud.service && die "Nextcloud PHP-FPM should still be stopped"
systemctl is-active --quiet podman-litellm.service && die "LiteLLM should still be stopped"

printf '%s  %s\n' "${litellm_dump_sha256}" "${litellm_dump}" | sha256sum --check -
assert_equal \
  "Restored Nextcloud files" \
  "$(find /srv/nextcloud/data -type f -printf '.' | wc -c)" \
  "${expected_nextcloud_files}"
assert_equal \
  "Restored Nextcloud tables" \
  "$(mysql_scalar "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'nextcloud';")" \
  "${expected_nextcloud_tables}"
assert_equal \
  "Restored Nextcloud users" \
  "$(mysql_scalar 'SELECT COUNT(*) FROM oc_users;')" \
  "${expected_nextcloud_users}"

nextcloud_status="$(nextcloud-occ status)"
echo "${nextcloud_status}"
grep --quiet -- "- maintenance: true" <<<"${nextcloud_status}" ||
  die "Nextcloud is not in maintenance mode"

install \
  --owner=postgres \
  --group=postgres \
  --mode=0400 \
  "${litellm_dump}" \
  "${postgres_litellm_dump}"
runuser --user=postgres -- pg_restore --list "${postgres_litellm_dump}" >/dev/null

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
printf 'resumed=%s\nresume_log=%s\ncompleted=%s\nprevious_data=%s\nstaging=%s\n' \
  "$(date -u --iso-8601=seconds)" \
  "${log_file}" \
  "$(date -u --iso-8601=seconds)" \
  "${previous_data}" \
  "${restore_input}" >>"${state_file}"
mv "${state_file}" "${complete_file}"
trap - ERR

echo
echo "Restore completed successfully after resume."
echo "Previous fresh Nextcloud data retained at: ${previous_data}"
echo "Restore input retained at: ${restore_input}"
echo "Log: ${log_file}"

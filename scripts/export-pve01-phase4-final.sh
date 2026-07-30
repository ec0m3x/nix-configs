#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly pve_host="${PVE_HOST:-root@pve01}"
readonly docker_host="${DOCKER_HOST:-ecomex@10.20.50.46}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ "${I_UNDERSTAND_PHASE4_MAINTENANCE:-}" != "yes" ]]; then
  die "set I_UNDERSTAND_PHASE4_MAINTENANCE=yes to enter the final maintenance window"
fi
if [[ "$#" -ne 3 ]]; then
  die "usage: $0 OUTPUT_DIRECTORY AGE_RECIPIENTS_FILE AGE_IDENTITY"
fi

readonly output_dir="$1"
readonly age_recipients_file="$2"
readonly age_identity="$3"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
readonly run_id
readonly paperless_export="/opt/paperless_data/export-final-${run_id}"
readonly docker_stage="/home/ecomex/.local/share/nix-configs-migration/hl01-final-${run_id}"
maintenance_started=0

[[ -f "${age_recipients_file}" ]] || die "missing age recipients file"
[[ -f "${age_identity}" ]] || die "missing age identity"
[[ ! -e "${output_dir}" ]] || die "output directory already exists: ${output_dir}"

on_error() {
  local exit_code=$?

  echo
  echo "Final export failed with exit code ${exit_code}."
  if [[ "${maintenance_started}" -eq 1 ]]; then
    echo "Source services are intentionally not restarted automatically."
    echo "Inspect the last successful artifact before either retrying or explicitly aborting maintenance."
  else
    echo "The failure occurred during preflight; source services were not stopped."
  fi
  exit "${exit_code}"
}
trap on_error ERR

echo "== Final Phase 4 source preflight =="
for command in age pg_restore ssh sqlite3 tar zstd; do
  command -v "${command}" >/dev/null || die "missing local command: ${command}"
done
ssh "${pve_host}" 'pvecm status >/dev/null'
ssh "${pve_host}" 'pct status 100; pct status 102; pct status 104; pct status 105'
ssh "${docker_host}" 'docker ps >/dev/null'
install --directory --mode=0700 "${output_dir}"

echo "== Stopping application writers =="
maintenance_started=1
ssh "${pve_host}" '
  set -e
  pct exec 102 -- systemctl stop immich-web.service immich-ml.service
  pct exec 104 -- systemctl stop \
    paperless-consumer.service \
    paperless-scheduler.service \
    paperless-task-queue.service \
    paperless-webserver.service
  pct exec 100 -- systemctl stop hermes-dashboard.service
  pct exec 105 -- systemctl stop open-webui.service
'
ssh "${docker_host}" '
  set -e
  docker stop \
    haushaltsbuch-scheduler-1 \
    haushaltsbuch-web-1 \
    honcho-deriver-1 \
    honcho-api-1 >/dev/null
'

echo "== Creating final Paperless exporter =="
ssh "${pve_host}" "
  set -e
  pct exec 104 -- test ! -e '${paperless_export}'
  pct exec 104 -- bash -lc '
    set -e
    export PAPERLESS_DATA_DIR=/opt/paperless_data/data
    export PAPERLESS_MEDIA_ROOT=/opt/paperless_data/media
    export PAPERLESS_CONSUMPTION_DIR=/opt/paperless_data/consume
    cd /opt/paperless/src
    uv run -- python manage.py document_exporter \"${paperless_export}\"
  '
"

echo "== Creating consistent Haushaltsbuch SQLite copy =="
ssh "${docker_host}" "install -d -m 700 '${docker_stage}'"
ssh "${docker_host}" \
  python3 - \
  /var/lib/docker/volumes/haushaltsbuch_hb-data/_data/haushaltsbuch.db \
  "${docker_stage}/haushaltsbuch.sqlite" <<'PYTHON'
import sqlite3
import sys

source_path, target_path = sys.argv[1:3]
with sqlite3.connect(f"file:{source_path}?mode=ro", uri=True) as source:
    with sqlite3.connect(target_path) as target:
        source.backup(target)
PYTHON

echo "== Recording stopped-source inventory =="
immich_files="$(
  ssh "${pve_host}" \
    "pct exec 102 -- bash -lc \"find /opt/immich/upload -type f -printf . | wc -c\""
)"
immich_assets="$(
  ssh "${pve_host}" \
    "pct exec 102 -- runuser --user=postgres -- psql --no-psqlrc --tuples-only --no-align --dbname=immich --command='SELECT COUNT(*) FROM asset;'"
)"
immich_users="$(
  ssh "${pve_host}" \
    "pct exec 102 -- runuser --user=postgres -- psql --no-psqlrc --tuples-only --no-align --dbname=immich --command='SELECT COUNT(*) FROM \"user\";'"
)"
paperless_export_files="$(
  ssh "${pve_host}" \
    "pct exec 104 -- bash -lc \"find '${paperless_export}' -type f -printf . | wc -c\""
)"
paperless_documents="$(
  ssh "${pve_host}" \
    "pct exec 104 -- runuser --user=postgres -- psql --no-psqlrc --tuples-only --no-align --dbname=paperlessdb --command='SELECT COUNT(*) FROM documents_document;'"
)"
paperless_users="$(
  ssh "${pve_host}" \
    "pct exec 104 -- runuser --user=postgres -- psql --no-psqlrc --tuples-only --no-align --dbname=paperlessdb --command='SELECT COUNT(*) FROM auth_user;'"
)"
paperless_media_files="$(
  ssh "${pve_host}" \
    "pct exec 104 -- bash -lc \"find /opt/paperless_data/media -type f -printf . | wc -c\""
)"
ava_entries="$(
  ssh "${pve_host}" \
    "pct exec 100 -- bash -lc \"find /home/hermes -mindepth 1 -printf . | wc -c\""
)"
ava_commit="$(
  ssh "${pve_host}" \
    'pct exec 100 -- git -C /home/hermes/.hermes/hermes-agent rev-parse HEAD'
)"
haushaltsbuch_tables="$(
  ssh "${docker_host}" \
    python3 - "${docker_stage}/haushaltsbuch.sqlite" <<'PYTHON'
import sqlite3
import sys

with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True) as database:
    quick_check = database.execute("PRAGMA quick_check").fetchone()[0]
    if quick_check != "ok":
        raise SystemExit(f"SQLite quick_check failed: {quick_check}")
    print(
        database.execute(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table'"
        ).fetchone()[0]
    )
PYTHON
)"
honcho_tables="$(
  ssh "${docker_host}" \
    "docker exec honcho-database-1 sh -lc 'psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -Atqc \"SELECT COUNT(*) FROM pg_tables WHERE schemaname = '\\''public'\\'';\"'"
)"

for numeric_value in \
  "${immich_files}" \
  "${immich_assets}" \
  "${immich_users}" \
  "${paperless_export_files}" \
  "${paperless_documents}" \
  "${paperless_users}" \
  "${paperless_media_files}" \
  "${ava_entries}" \
  "${haushaltsbuch_tables}" \
  "${honcho_tables}"; do
  [[ "${numeric_value}" =~ ^[0-9]+$ ]] || die "invalid source inventory value"
done
[[ "${ava_commit}" =~ ^[0-9a-f]{40}$ ]] || die "invalid AVA commit"

{
  printf 'run_id=%s\n' "${run_id}"
  printf 'immich_files=%s\n' "${immich_files}"
  printf 'immich_assets=%s\n' "${immich_assets}"
  printf 'immich_users=%s\n' "${immich_users}"
  printf 'paperless_export_files=%s\n' "${paperless_export_files}"
  printf 'paperless_documents=%s\n' "${paperless_documents}"
  printf 'paperless_users=%s\n' "${paperless_users}"
  printf 'paperless_media_files=%s\n' "${paperless_media_files}"
  printf 'ava_entries=%s\n' "${ava_entries}"
  printf 'ava_commit=%s\n' "${ava_commit}"
  printf 'haushaltsbuch_tables=%s\n' "${haushaltsbuch_tables}"
  printf 'honcho_tables=%s\n' "${honcho_tables}"
} >"${output_dir}/RESTORE-METADATA"

echo "== Streaming encrypted final exports =="
ssh "${pve_host}" \
  'pct exec 102 -- runuser --user=postgres -- pg_dump --format=custom --dbname=immich' |
  age --encrypt \
    --recipients-file "${age_recipients_file}" \
    --output "${output_dir}/immich-postgres.dump.age"
ssh "${pve_host}" \
  'pct exec 102 -- tar --create --file=- --directory=/ opt/immich/upload' |
  zstd --threads=0 --quiet |
  age --encrypt \
    --recipients-file "${age_recipients_file}" \
    --output "${output_dir}/immich-upload.tar.zst.age"

ssh "${pve_host}" \
  'pct exec 104 -- runuser --user=postgres -- pg_dump --format=custom --dbname=paperlessdb' |
  age --encrypt \
    --recipients-file "${age_recipients_file}" \
    --output "${output_dir}/paperless-postgres.dump.age"
ssh "${pve_host}" \
  'pct exec 104 -- tar --create --file=- --directory=/ opt/paperless_data' |
  zstd --threads=0 --quiet |
  age --encrypt \
    --recipients-file "${age_recipients_file}" \
    --output "${output_dir}/paperless-data.tar.zst.age"

ssh "${pve_host}" \
  'pct exec 100 -- tar --create --file=- --directory=/ home/hermes' |
  zstd --threads=0 --quiet |
  age --encrypt \
    --recipients-file "${age_recipients_file}" \
    --output "${output_dir}/ava-home.tar.zst.age"
ssh "${pve_host}" \
  'pct exec 105 -- tar --create --file=- --directory=/ root/.open-webui' |
  zstd --threads=0 --quiet |
  age --encrypt \
    --recipients-file "${age_recipients_file}" \
    --output "${output_dir}/openwebui-state.tar.zst.age"

ssh "${docker_host}" "cat '${docker_stage}/haushaltsbuch.sqlite'" |
  age --encrypt \
    --recipients-file "${age_recipients_file}" \
    --output "${output_dir}/haushaltsbuch.sqlite.age"
ssh "${docker_host}" \
  "docker exec honcho-database-1 sh -lc 'pg_dump -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" --format=custom'" |
  age --encrypt \
    --recipients-file "${age_recipients_file}" \
    --output "${output_dir}/honcho-postgres.dump.age"

echo "== Finalizing source maintenance state =="
ssh "${docker_host}" 'docker stop honcho-database-1 honcho-redis-1 >/dev/null'
ssh "${docker_host}" "find '${docker_stage}' -depth -delete"

(
  cd "${output_dir}"
  if command -v sha256sum >/dev/null; then
    sha256sum ./*.age >SHA256SUMS
  else
    shasum -a 256 ./*.age >SHA256SUMS
  fi
)

echo "== Verifying every final encrypted artifact =="
age --decrypt --identity "${age_identity}" "${output_dir}/immich-postgres.dump.age" |
  pg_restore --list - >/dev/null
age --decrypt --identity "${age_identity}" "${output_dir}/paperless-postgres.dump.age" |
  pg_restore --list - >/dev/null
age --decrypt --identity "${age_identity}" "${output_dir}/honcho-postgres.dump.age" |
  pg_restore --list - >/dev/null

for archive in \
  immich-upload.tar.zst.age \
  paperless-data.tar.zst.age \
  ava-home.tar.zst.age \
  openwebui-state.tar.zst.age; do
  age --decrypt --identity "${age_identity}" "${output_dir}/${archive}" |
    zstd --decompress --stdout |
    tar --list --file=- >/dev/null
done

verify_root="$(mktemp -d /tmp/hl01-final-export-verify.XXXXXX)"
age \
  --decrypt \
  --identity "${age_identity}" \
  --output "${verify_root}/haushaltsbuch.sqlite" \
  "${output_dir}/haushaltsbuch.sqlite.age"
[[ "$(sqlite3 "${verify_root}/haushaltsbuch.sqlite" 'PRAGMA quick_check;')" == "ok" ]] ||
  die "final Haushaltsbuch SQLite quick_check failed"
[[ "$(
  sqlite3 \
    "${verify_root}/haushaltsbuch.sqlite" \
    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table';"
)" == "${haushaltsbuch_tables}" ]] || die "final Haushaltsbuch table count changed"
find "${verify_root}" -depth -delete

trap - ERR

echo
echo "Final encrypted Phase 4 export completed."
echo "Source application writers remain stopped."
echo "Output: ${output_dir}"
echo "Verify and copy this directory before shutting down the guests."

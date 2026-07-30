#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 POSTGRES_BIN SQL_QUERY [SQL_QUERY ...]" >&2
  echo "reads a custom-format pg_dump from stdin" >&2
  exit 2
fi

postgres_bin=$1
shift

if [[ ! -x "$postgres_bin/initdb" ]]; then
  echo "PostgreSQL bin directory is invalid: $postgres_bin" >&2
  exit 2
fi

test_root=$(mktemp -d /tmp/hl01-postgres-restore.XXXXXX)
data_dir=$test_root/data
socket_dir=$test_root/run
mkdir -m 700 "$socket_dir"

cleanup() {
  if [[ -s "$data_dir/postmaster.pid" ]]; then
    "$postgres_bin/pg_ctl" -D "$data_dir" -m immediate -w stop >/dev/null
  fi
  find "$test_root" -depth -delete
}
trap cleanup EXIT

"$postgres_bin/initdb" \
  --auth=trust \
  --encoding=UTF8 \
  --locale=C.UTF-8 \
  -D "$data_dir" >/dev/null

server_options="-k $socket_dir -h ''"
if [[ -e "${postgres_bin%/bin}/lib/vchord.so" ]]; then
  server_options+=" -c shared_preload_libraries=vchord.so"
fi

"$postgres_bin/pg_ctl" \
  -D "$data_dir" \
  -o "$server_options" \
  -w start >/dev/null

export PGHOST=$socket_dir
"$postgres_bin/createdb" restorecheck
"$postgres_bin/pg_restore" \
  --exit-on-error \
  --no-owner \
  --no-privileges \
  --dbname=restorecheck

for query in "$@"; do
  "$postgres_bin/psql" \
    --no-psqlrc \
    --tuples-only \
    --no-align \
    --dbname=restorecheck \
    --command="$query"
done

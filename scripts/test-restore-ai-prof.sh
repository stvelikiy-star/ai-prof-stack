#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

BACKUP_ROOT="/home/agent/ai-prof-backups"
TEST_DATABASE="n8n_restore_test"

LATEST_BACKUP="$(
  find "$BACKUP_ROOT" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    | sort \
    | tail -n 1
)"

if [ -z "$LATEST_BACKUP" ]; then
  echo "ERROR: No backup directory was found." >&2
  exit 1
fi

DUMP_FILE="$LATEST_BACKUP/database/n8n.dump"
VOLUME_ARCHIVE="$LATEST_BACKUP/volumes/n8n-data.tar.gz"
CONFIG_ARCHIVE="$LATEST_BACKUP/config/ai-prof-config.tar.gz"

if [ ! -s "$DUMP_FILE" ]; then
  echo "ERROR: PostgreSQL dump is missing or empty." >&2
  exit 1
fi

if [ ! -s "$VOLUME_ARCHIVE" ]; then
  echo "ERROR: n8n volume archive is missing or empty." >&2
  exit 1
fi

if [ ! -s "$CONFIG_ARCHIVE" ]; then
  echo "ERROR: Configuration archive is missing or empty." >&2
  exit 1
fi

cleanup() {
  local exit_code=$?

  trap - EXIT

  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname=postgres \
      --tuples-only \
      --no-align \
      --command="
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '$TEST_DATABASE'
          AND pid <> pg_backend_pid();
      " >/dev/null 2>&1 || true

  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname=postgres \
      --command="DROP DATABASE IF EXISTS $TEST_DATABASE;" \
      >/dev/null 2>&1 || true

  exit "$exit_code"
}

trap cleanup EXIT

echo "=== BACKUP ==="
echo "$LATEST_BACKUP"

echo "=== CHECKSUM VERIFICATION ==="

cd "$LATEST_BACKUP"
sha256sum --check SHA256SUMS

echo "=== ARCHIVE VERIFICATION ==="

docker run \
  --rm \
  --network none \
  --volume "$LATEST_BACKUP/database:/backup:ro" \
  postgres:17-alpine \
  pg_restore \
    --list \
    /backup/n8n.dump \
  >/dev/null

tar -tzf "$VOLUME_ARCHIVE" >/dev/null
tar -tzf "$CONFIG_ARCHIVE" >/dev/null

echo "=== SOURCE DATABASE METRICS ==="

SOURCE_TABLES="$(
  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname=n8n \
      --tuples-only \
      --no-align \
      --command="
        SELECT count(*)
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_type = 'BASE TABLE';
      "
)"

SOURCE_MIGRATIONS="$(
  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname=n8n \
      --tuples-only \
      --no-align \
      --command="
        SELECT CASE
          WHEN to_regclass('public.migrations') IS NULL THEN -1
          ELSE (SELECT count(*) FROM public.migrations)
        END;
      "
)"

SOURCE_USERS="$(
  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname=n8n \
      --tuples-only \
      --no-align \
      --command="
        SELECT CASE
          WHEN to_regclass('public.\"user\"') IS NULL THEN -1
          ELSE (SELECT count(*) FROM public.\"user\")
        END;
      "
)"

SOURCE_WORKFLOWS="$(
  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname=n8n \
      --tuples-only \
      --no-align \
      --command="
        SELECT CASE
          WHEN to_regclass('public.workflow_entity') IS NULL THEN -1
          ELSE (SELECT count(*) FROM public.workflow_entity)
        END;
      "
)"

echo "Source tables: $SOURCE_TABLES"
echo "Source migrations: $SOURCE_MIGRATIONS"
echo "Source users: $SOURCE_USERS"
echo "Source workflows: $SOURCE_WORKFLOWS"

echo "=== CREATE TEMPORARY DATABASE ==="

docker exec ai-prof-postgres \
  psql \
    --username=postgres \
    --dbname=postgres \
    --command="
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = '$TEST_DATABASE'
        AND pid <> pg_backend_pid();
    " \
  >/dev/null

docker exec ai-prof-postgres \
  psql \
    --username=postgres \
    --dbname=postgres \
    --command="DROP DATABASE IF EXISTS $TEST_DATABASE;" \
  >/dev/null

docker exec ai-prof-postgres \
  createdb \
    --username=postgres \
    --owner=n8n \
    --encoding=UTF8 \
    --template=template0 \
    "$TEST_DATABASE"

echo "=== RESTORE BACKUP ==="

docker exec -i ai-prof-postgres \
  pg_restore \
    --username=postgres \
    --dbname="$TEST_DATABASE" \
    --role=n8n \
    --no-owner \
    --no-acl \
    --exit-on-error \
  < "$DUMP_FILE"

echo "=== RESTORED DATABASE METRICS ==="

RESTORED_TABLES="$(
  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname="$TEST_DATABASE" \
      --tuples-only \
      --no-align \
      --command="
        SELECT count(*)
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_type = 'BASE TABLE';
      "
)"

RESTORED_MIGRATIONS="$(
  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname="$TEST_DATABASE" \
      --tuples-only \
      --no-align \
      --command="
        SELECT CASE
          WHEN to_regclass('public.migrations') IS NULL THEN -1
          ELSE (SELECT count(*) FROM public.migrations)
        END;
      "
)"

RESTORED_USERS="$(
  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname="$TEST_DATABASE" \
      --tuples-only \
      --no-align \
      --command="
        SELECT CASE
          WHEN to_regclass('public.\"user\"') IS NULL THEN -1
          ELSE (SELECT count(*) FROM public.\"user\")
        END;
      "
)"

RESTORED_WORKFLOWS="$(
  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname="$TEST_DATABASE" \
      --tuples-only \
      --no-align \
      --command="
        SELECT CASE
          WHEN to_regclass('public.workflow_entity') IS NULL THEN -1
          ELSE (SELECT count(*) FROM public.workflow_entity)
        END;
      "
)"

RESTORED_OWNER="$(
  docker exec ai-prof-postgres \
    psql \
      --username=postgres \
      --dbname=postgres \
      --tuples-only \
      --no-align \
      --command="
        SELECT pg_get_userbyid(datdba)
        FROM pg_database
        WHERE datname = '$TEST_DATABASE';
      "
)"

echo "Restored tables: $RESTORED_TABLES"
echo "Restored migrations: $RESTORED_MIGRATIONS"
echo "Restored users: $RESTORED_USERS"
echo "Restored workflows: $RESTORED_WORKFLOWS"
echo "Restored database owner: $RESTORED_OWNER"

if [ "$SOURCE_TABLES" != "$RESTORED_TABLES" ]; then
  echo "ERROR: Table counts do not match." >&2
  exit 1
fi

if [ "$SOURCE_MIGRATIONS" != "$RESTORED_MIGRATIONS" ]; then
  echo "ERROR: Migration counts do not match." >&2
  exit 1
fi

if [ "$SOURCE_USERS" != "$RESTORED_USERS" ]; then
  echo "ERROR: User counts do not match." >&2
  exit 1
fi

if [ "$SOURCE_WORKFLOWS" != "$RESTORED_WORKFLOWS" ]; then
  echo "ERROR: Workflow counts do not match." >&2
  exit 1
fi

if [ "$RESTORED_OWNER" != "n8n" ]; then
  echo "ERROR: Restored database owner is not n8n." >&2
  exit 1
fi

echo "=== N8N VOLUME ARCHIVE CONTENTS ==="

tar -tzf "$VOLUME_ARCHIVE" | sed -n '1,40p'

echo "=== WORKING SERVICES ==="

POSTGRES_HEALTH="$(
  docker inspect \
    --format='{{.State.Health.Status}}' \
    ai-prof-postgres
)"

N8N_HEALTH="$(
  docker inspect \
    --format='{{.State.Health.Status}}' \
    ai-prof-n8n
)"

HTTP_CODE="$(
  curl \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out='%{http_code}' \
    http://127.0.0.1:5678/healthz/readiness
)"

if [ "$POSTGRES_HEALTH" != "healthy" ]; then
  echo "ERROR: PostgreSQL is not healthy." >&2
  exit 1
fi

if [ "$N8N_HEALTH" != "healthy" ]; then
  echo "ERROR: n8n is not healthy." >&2
  exit 1
fi

if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: n8n readiness returned HTTP $HTTP_CODE." >&2
  exit 1
fi

echo "PostgreSQL: $POSTGRES_HEALTH"
echo "n8n: $N8N_HEALTH"
echo "Readiness HTTP: $HTTP_CODE"

echo "=== REMOVE TEMPORARY DATABASE ==="

docker exec ai-prof-postgres \
  psql \
    --username=postgres \
    --dbname=postgres \
    --command="DROP DATABASE $TEST_DATABASE;" \
  >/dev/null

trap - EXIT

echo "Temporary database removed: $TEST_DATABASE"
echo "RESTORE TEST: PASS"

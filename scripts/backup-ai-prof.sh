#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

STACK_DIR="/home/agent/ai-prof-stack"
BACKUP_ROOT="/home/agent/ai-prof-backups"
RETENTION_DAYS=14

TIMESTAMP="$(date '+%Y-%m-%d_%H%M%S')"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
LOG_FILE="${BACKUP_DIR}/backup.log"

N8N_STOPPED=0

dc() {
  docker compose \
    --project-directory "$STACK_DIR" \
    --file "$STACK_DIR/compose.yaml" \
    "$@"
}

mkdir -p \
  "$BACKUP_DIR/database" \
  "$BACKUP_DIR/volumes" \
  "$BACKUP_DIR/config"

exec > >(tee -a "$LOG_FILE") 2>&1

cleanup() {
  local exit_code=$?

  trap - EXIT

  if [ "$N8N_STOPPED" -eq 1 ]; then
    echo "Restoring the n8n service after an interrupted backup."
    dc up -d n8n || true
  fi

  exit "$exit_code"
}

trap cleanup EXIT

echo "AI PROF backup started: $(date --iso-8601=seconds)"
echo "Backup directory: $BACKUP_DIR"

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

if [ "$POSTGRES_HEALTH" != "healthy" ]; then
  echo "ERROR: PostgreSQL is not healthy." >&2
  exit 1
fi

if [ "$N8N_HEALTH" != "healthy" ]; then
  echo "ERROR: n8n is not healthy." >&2
  exit 1
fi

echo "Stopping n8n for a consistent backup."
dc stop n8n
N8N_STOPPED=1

echo "Creating the PostgreSQL custom-format dump."

docker exec ai-prof-postgres \
  pg_dump \
    --username=postgres \
    --dbname=n8n \
    --format=custom \
    --no-owner \
    --no-acl \
  > "$BACKUP_DIR/database/n8n.dump"

test -s "$BACKUP_DIR/database/n8n.dump"

echo "Archiving the persistent n8n Docker volume."

docker run \
  --rm \
  --network none \
  --volume ai-prof-n8n-data:/source:ro \
  --volume "$BACKUP_DIR/volumes:/backup" \
  postgres:17-alpine \
  sh -c 'tar -czf /backup/n8n-data.tar.gz -C /source .'

test -s "$BACKUP_DIR/volumes/n8n-data.tar.gz"

echo "Archiving the non-secret infrastructure configuration."

cd "$STACK_DIR"

CONFIG_ITEMS=(
  compose.yaml
  postgres
  n8n
  ai-system
  scripts
)

if [ -f ".gitignore" ]; then
  CONFIG_ITEMS+=(".gitignore")
fi

tar \
  --exclude='secrets' \
  --exclude='.env' \
  --exclude='*.key' \
  --exclude='*.pem' \
  -czf "$BACKUP_DIR/config/ai-prof-config.tar.gz" \
  "${CONFIG_ITEMS[@]}"

test -s "$BACKUP_DIR/config/ai-prof-config.tar.gz"

echo "Creating SHA-256 checksums."

cd "$BACKUP_DIR"

find database volumes config \
  -type f \
  -print0 \
  | sort -z \
  | xargs -0 sha256sum \
  > SHA256SUMS

echo "Validating the PostgreSQL dump."

docker run \
  --rm \
  --network none \
  --volume "$BACKUP_DIR/database:/backup:ro" \
  postgres:17-alpine \
  pg_restore \
    --list \
    /backup/n8n.dump \
  > /dev/null

echo "Validating archive structures."

tar -tzf "$BACKUP_DIR/volumes/n8n-data.tar.gz" > /dev/null
tar -tzf "$BACKUP_DIR/config/ai-prof-config.tar.gz" > /dev/null

echo "Validating checksums."

sha256sum --check SHA256SUMS

echo "Starting n8n."

dc up -d n8n

for attempt in $(seq 1 36); do
  N8N_HEALTH="$(
    docker inspect \
      --format='{{.State.Health.Status}}' \
      ai-prof-n8n 2>/dev/null || echo missing
  )"

  echo "n8n health: $N8N_HEALTH"

  if [ "$N8N_HEALTH" = "healthy" ]; then
    break
  fi

  sleep 5
done

if [ "$N8N_HEALTH" != "healthy" ]; then
  echo "ERROR: n8n did not return to healthy status." >&2
  exit 1
fi

HTTP_CODE="$(
  curl \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    http://127.0.0.1:5678/healthz/readiness
)"

if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: n8n readiness returned HTTP $HTTP_CODE." >&2
  exit 1
fi

N8N_STOPPED=0

echo "Removing backup directories older than $RETENTION_DAYS days."

find "$BACKUP_ROOT" \
  -mindepth 1 \
  -maxdepth 1 \
  -type d \
  -mtime +"$RETENTION_DAYS" \
  -print \
  -exec rm -rf -- {} +

echo "AI PROF backup completed successfully: $(date --iso-8601=seconds)"
echo "PostgreSQL: healthy"
echo "n8n: healthy"
echo "Readiness HTTP: $HTTP_CODE"
echo "Backup directory: $BACKUP_DIR"

trap - EXIT

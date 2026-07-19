#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

BACKUP_ROOT="/home/agent/ai-prof-backups"

DISK_WARNING=80
DISK_CRITICAL=90

RAM_AVAILABLE_WARNING=15
RAM_AVAILABLE_CRITICAL=8

SWAP_WARNING=50
SWAP_CRITICAL=80

BACKUP_WARNING_HOURS=36
BACKUP_CRITICAL_HOURS=60

WARNINGS=0
CRITICALS=0

ok() {
  printf '[OK] %s\n' "$1"
}

warning() {
  WARNINGS=$((WARNINGS + 1))
  printf '[WARNING] %s\n' "$1"
}

critical() {
  CRITICALS=$((CRITICALS + 1))
  printf '[CRITICAL] %s\n' "$1"
}

echo "=== AI PROF SERVER HEALTH CHECK ==="
echo "Time: $(date --iso-8601=seconds)"
echo "Host: $(hostname)"
echo

echo "=== DISK ==="

DISK_USED_PERCENT="$(
  df -P / |
    awk 'NR == 2 {gsub("%", "", $5); print $5}'
)"

DISK_SUMMARY="$(
  df -hP / |
    awk 'NR == 2 {print $3 " used of " $2 ", usage " $5}'
)"

if [ "$DISK_USED_PERCENT" -ge "$DISK_CRITICAL" ]; then
  critical "Root filesystem: $DISK_SUMMARY"
elif [ "$DISK_USED_PERCENT" -ge "$DISK_WARNING" ]; then
  warning "Root filesystem: $DISK_SUMMARY"
else
  ok "Root filesystem: $DISK_SUMMARY"
fi

echo
echo "=== MEMORY ==="

MEM_TOTAL_KB="$(
  awk '/^MemTotal:/ {print $2}' /proc/meminfo
)"

MEM_AVAILABLE_KB="$(
  awk '/^MemAvailable:/ {print $2}' /proc/meminfo
)"

MEM_AVAILABLE_PERCENT="$(
  awk -v available="$MEM_AVAILABLE_KB" -v total="$MEM_TOTAL_KB" \
    'BEGIN {printf "%.0f", (available / total) * 100}'
)"

MEM_USED_KB=$((MEM_TOTAL_KB - MEM_AVAILABLE_KB))

MEM_TOTAL_HUMAN="$(
  numfmt --from-unit=1024 --to=iec-i --suffix=B "$MEM_TOTAL_KB"
)"

MEM_USED_HUMAN="$(
  numfmt --from-unit=1024 --to=iec-i --suffix=B "$MEM_USED_KB"
)"

MEM_AVAILABLE_HUMAN="$(
  numfmt --from-unit=1024 --to=iec-i --suffix=B "$MEM_AVAILABLE_KB"
)"

MEM_SUMMARY="${MEM_USED_HUMAN} used of ${MEM_TOTAL_HUMAN}, ${MEM_AVAILABLE_HUMAN} available"

if [ "$MEM_AVAILABLE_PERCENT" -le "$RAM_AVAILABLE_CRITICAL" ]; then
  critical "RAM: $MEM_SUMMARY (${MEM_AVAILABLE_PERCENT}% available)"
elif [ "$MEM_AVAILABLE_PERCENT" -le "$RAM_AVAILABLE_WARNING" ]; then
  warning "RAM: $MEM_SUMMARY (${MEM_AVAILABLE_PERCENT}% available)"
else
  ok "RAM: $MEM_SUMMARY (${MEM_AVAILABLE_PERCENT}% available)"
fi

SWAP_TOTAL_KB="$(
  awk '/^SwapTotal:/ {print $2}' /proc/meminfo
)"

SWAP_FREE_KB="$(
  awk '/^SwapFree:/ {print $2}' /proc/meminfo
)"

if [ "$SWAP_TOTAL_KB" -eq 0 ]; then
  warning "Swap is not configured."
else
  SWAP_USED_KB=$((SWAP_TOTAL_KB - SWAP_FREE_KB))

  SWAP_USED_PERCENT="$(
    awk -v used="$SWAP_USED_KB" -v total="$SWAP_TOTAL_KB" \
      'BEGIN {printf "%.0f", (used / total) * 100}'
  )"

  SWAP_TOTAL_HUMAN="$(
    numfmt --from-unit=1024 --to=iec-i --suffix=B "$SWAP_TOTAL_KB"
  )"

  SWAP_USED_HUMAN="$(
    numfmt --from-unit=1024 --to=iec-i --suffix=B "$SWAP_USED_KB"
  )"

  SWAP_SUMMARY="${SWAP_USED_HUMAN} used of ${SWAP_TOTAL_HUMAN}"

  if [ "$SWAP_USED_PERCENT" -ge "$SWAP_CRITICAL" ]; then
    critical "Swap: $SWAP_SUMMARY (${SWAP_USED_PERCENT}% used)"
  elif [ "$SWAP_USED_PERCENT" -ge "$SWAP_WARNING" ]; then
    warning "Swap: $SWAP_SUMMARY (${SWAP_USED_PERCENT}% used)"
  else
    ok "Swap: $SWAP_SUMMARY (${SWAP_USED_PERCENT}% used)"
  fi
fi

echo
echo "=== DOCKER ==="

if systemctl is-enabled --quiet docker; then
  ok "Docker service is enabled."
else
  warning "Docker service is not enabled."
fi

DOCKER_ACTIVE=0

if systemctl is-active --quiet docker; then
  DOCKER_ACTIVE=1
  ok "Docker service is active."
else
  critical "Docker service is not active."
fi

check_container() {
  local container_name="$1"
  local display_name="$2"

  if ! docker inspect "$container_name" >/dev/null 2>&1; then
    critical "$display_name container does not exist."
    return
  fi

  local state
  local health

  state="$(
    docker inspect \
      --format='{{.State.Status}}' \
      "$container_name"
  )"

  health="$(
    docker inspect \
      --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}not-configured{{end}}' \
      "$container_name"
  )"

  if [ "$state" != "running" ]; then
    critical "$display_name container state: $state"
  elif [ "$health" != "healthy" ]; then
    critical "$display_name container health: $health"
  else
    ok "$display_name container: running and healthy."
  fi
}

if [ "$DOCKER_ACTIVE" -eq 1 ]; then
  check_container "ai-prof-postgres" "PostgreSQL"
  check_container "ai-prof-n8n" "n8n"
fi

echo
echo "=== N8N READINESS ==="

HTTP_CODE="$(
  curl \
    --silent \
    --show-error \
    --max-time 10 \
    --output /dev/null \
    --write-out='%{http_code}' \
    http://127.0.0.1:5678/healthz/readiness \
    2>/dev/null ||
    true
)"

if [ "$HTTP_CODE" = "200" ]; then
  ok "n8n readiness HTTP: 200"
else
  critical "n8n readiness HTTP: ${HTTP_CODE:-connection-failed}"
fi

echo
echo "=== BACKUP TIMER ==="

if systemctl is-enabled --quiet ai-prof-backup.timer; then
  ok "Backup timer is enabled."
else
  critical "Backup timer is not enabled."
fi

if systemctl is-active --quiet ai-prof-backup.timer; then
  ok "Backup timer is active."
else
  critical "Backup timer is not active."
fi

NEXT_BACKUP="$(
  systemctl show ai-prof-backup.timer \
    --property=NextElapseUSecRealtime \
    --value \
    2>/dev/null ||
    true
)"

if [ -n "$NEXT_BACKUP" ] && [ "$NEXT_BACKUP" != "n/a" ]; then
  ok "Next scheduled backup: $NEXT_BACKUP"
else
  warning "The next backup time could not be determined."
fi

echo
echo "=== LATEST BACKUP ==="

LATEST_BACKUP="$(
  find "$BACKUP_ROOT" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -printf '%T@ %p\n' \
    2>/dev/null |
    sort -nr |
    head -n 1 |
    cut -d' ' -f2- ||
    true
)"

if [ -z "$LATEST_BACKUP" ]; then
  critical "No backup directory was found."
else
  BACKUP_TIMESTAMP="$(
    stat -c '%Y' "$LATEST_BACKUP"
  )"

  CURRENT_TIMESTAMP="$(
    date '+%s'
  )"

  BACKUP_AGE_HOURS=$((
    (CURRENT_TIMESTAMP - BACKUP_TIMESTAMP) / 3600
  ))

  MISSING_FILES=0

  REQUIRED_FILES=(
    "database/n8n.dump"
    "volumes/n8n-data.tar.gz"
    "config/ai-prof-config.tar.gz"
    "SHA256SUMS"
    "backup.log"
  )

  for REQUIRED_FILE in "${REQUIRED_FILES[@]}"; do
    if [ ! -s "$LATEST_BACKUP/$REQUIRED_FILE" ]; then
      critical "Missing or empty backup file: $REQUIRED_FILE"
      MISSING_FILES=$((MISSING_FILES + 1))
    fi
  done

  if [ "$MISSING_FILES" -eq 0 ]; then
    ok "All required files exist in the latest backup."
  fi

  if [ "$BACKUP_AGE_HOURS" -ge "$BACKUP_CRITICAL_HOURS" ]; then
    critical "Latest backup is ${BACKUP_AGE_HOURS} hours old: $LATEST_BACKUP"
  elif [ "$BACKUP_AGE_HOURS" -ge "$BACKUP_WARNING_HOURS" ]; then
    warning "Latest backup is ${BACKUP_AGE_HOURS} hours old: $LATEST_BACKUP"
  else
    ok "Latest backup is ${BACKUP_AGE_HOURS} hours old: $LATEST_BACKUP"
  fi
fi

echo
echo "=== RESULT ==="
echo "Warnings: $WARNINGS"
echo "Critical problems: $CRITICALS"

if [ "$CRITICALS" -gt 0 ]; then
  echo "HEALTH CHECK: CRITICAL"
  exit 2
fi

if [ "$WARNINGS" -gt 0 ]; then
  echo "HEALTH CHECK: WARNING"
  exit 1
fi

echo "HEALTH CHECK: PASS"
exit 0

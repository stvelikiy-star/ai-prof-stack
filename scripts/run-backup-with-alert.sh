#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

STACK_DIR="/home/agent/ai-prof-stack"
BACKUP_SCRIPT="$STACK_DIR/scripts/backup-ai-prof.sh"
ALERT_SCRIPT="$STACK_DIR/scripts/send-telegram-alert.sh"
STATE_FILE="$STACK_DIR/runtime/backup-alert-state"
LOCK_FILE="$STACK_DIR/runtime/backup-alert.lock"

if [ ! -x "$BACKUP_SCRIPT" ]; then
  echo "ERROR: Backup script is missing or not executable." >&2
  exit 2
fi

if [ ! -x "$ALERT_SCRIPT" ]; then
  echo "ERROR: Telegram alert script is missing or not executable." >&2
  exit 2
fi

mkdir -p "$STACK_DIR/runtime"
chmod 700 "$STACK_DIR/runtime"

exec 9>"$LOCK_FILE"
chmod 600 "$LOCK_FILE"

if ! flock -n 9; then
  echo "ERROR: Another backup execution is already running." >&2
  exit 75
fi

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

PREVIOUS_LEVEL="NONE"
PREVIOUS_FINGERPRINT=""
PREVIOUS_TIMESTAMP=""

if [ -s "$STATE_FILE" ]; then
  IFS='|' read -r \
    PREVIOUS_LEVEL \
    PREVIOUS_FINGERPRINT \
    PREVIOUS_TIMESTAMP \
    < "$STATE_FILE" || true
fi

set +e
"$BACKUP_SCRIPT" >"$OUTPUT_FILE" 2>&1
BACKUP_EXIT_CODE=$?
set -e

cat "$OUTPUT_FILE"

if [ "$BACKUP_EXIT_CODE" -eq 0 ]; then
  if [ "$PREVIOUS_LEVEL" = "CRITICAL" ]; then
    RECOVERY_MESSAGE="$(
      printf 'Backup service recovered.\nHost: %s\nTime: %s\nPrevious state: CRITICAL\nCurrent state: PASS' \
        "$(hostname)" \
        "$(date --iso-8601=seconds)"
    )"

    if ! "$ALERT_SCRIPT" RECOVERY "$RECOVERY_MESSAGE"; then
      echo "ERROR: Backup recovery notification could not be delivered." >&2
      exit 1
    fi
  fi

  printf 'PASS||%s\n' \
    "$(date --iso-8601=seconds)" \
    > "$STATE_FILE"

  chmod 600 "$STATE_FILE"

  echo "BACKUP ALERT WRAPPER: PASS"
  exit 0
fi

PROBLEM_LINES="$(
  grep -E \
    '^(ERROR:|AI PROF backup|Backup directory:|PostgreSQL:|n8n:|Readiness HTTP:)' \
    "$OUTPUT_FILE" ||
  true
)"

if [ -z "$PROBLEM_LINES" ]; then
  PROBLEM_LINES="$(
    tail -n 30 "$OUTPUT_FILE"
  )"
fi

PROBLEM_LINES="$(
  printf '%s\n' "$PROBLEM_LINES" |
    head -c 2800
)"

CURRENT_FINGERPRINT="$(
  printf '%s\n%s\n' \
    "$BACKUP_EXIT_CODE" \
    "$PROBLEM_LINES" |
    sha256sum |
    awk '{print $1}'
)"

if [ "$PREVIOUS_LEVEL" != "CRITICAL" ] ||
   [ "$CURRENT_FINGERPRINT" != "$PREVIOUS_FINGERPRINT" ]; then

  ALERT_MESSAGE="$(
    printf 'Backup failure detected.\nHost: %s\nTime: %s\nExit code: %s\n\n%s\n\nLog: journalctl -u ai-prof-backup.service' \
      "$(hostname)" \
      "$(date --iso-8601=seconds)" \
      "$BACKUP_EXIT_CODE" \
      "$PROBLEM_LINES"
  )"

  if ! "$ALERT_SCRIPT" CRITICAL "$ALERT_MESSAGE"; then
    echo "ERROR: Backup failure notification could not be delivered." >&2
    exit "$BACKUP_EXIT_CODE"
  fi
else
  echo "Telegram alert suppressed: the backup problem has not changed."
fi

printf 'CRITICAL|%s|%s\n' \
  "$CURRENT_FINGERPRINT" \
  "$(date --iso-8601=seconds)" \
  > "$STATE_FILE"

chmod 600 "$STATE_FILE"

exit "$BACKUP_EXIT_CODE"

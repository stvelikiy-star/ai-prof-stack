#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

STACK_DIR="/home/agent/ai-prof-stack"
HEALTH_SCRIPT="$STACK_DIR/scripts/check-ai-prof-health.sh"
ALERT_SCRIPT="$STACK_DIR/scripts/send-telegram-alert.sh"
STATE_FILE="$STACK_DIR/runtime/health-alert-state"

if [ ! -x "$HEALTH_SCRIPT" ]; then
  echo "ERROR: Health-check script is missing or not executable." >&2
  exit 2
fi

if [ ! -x "$ALERT_SCRIPT" ]; then
  echo "ERROR: Telegram alert script is missing or not executable." >&2
  exit 2
fi

mkdir -p "$STACK_DIR/runtime"
chmod 700 "$STACK_DIR/runtime"

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

set +e
"$HEALTH_SCRIPT" >"$OUTPUT_FILE" 2>&1
HEALTH_EXIT_CODE=$?
set -e

cat "$OUTPUT_FILE"

case "$HEALTH_EXIT_CODE" in
  0)
    CURRENT_LEVEL="PASS"
    ;;
  1)
    CURRENT_LEVEL="WARNING"
    ;;
  2)
    CURRENT_LEVEL="CRITICAL"
    ;;
  *)
    CURRENT_LEVEL="CRITICAL"
    ;;
esac

PREVIOUS_LEVEL="NONE"
PREVIOUS_FINGERPRINT=""

if [ -s "$STATE_FILE" ]; then
  IFS='|' read -r \
    PREVIOUS_LEVEL \
    PREVIOUS_FINGERPRINT \
    PREVIOUS_TIMESTAMP \
    < "$STATE_FILE" || true
fi

if [ "$CURRENT_LEVEL" = "PASS" ]; then
  if [ "$PREVIOUS_LEVEL" = "WARNING" ] ||
     [ "$PREVIOUS_LEVEL" = "CRITICAL" ]; then

    RECOVERY_MESSAGE="$(
      printf 'Server health recovered.\nHost: %s\nTime: %s\nPrevious state: %s\nCurrent state: PASS' \
        "$(hostname)" \
        "$(date --iso-8601=seconds)" \
        "$PREVIOUS_LEVEL"
    )"

    if ! "$ALERT_SCRIPT" RECOVERY "$RECOVERY_MESSAGE"; then
      echo "ERROR: Recovery notification could not be delivered." >&2
    fi
  fi

  printf 'PASS||%s\n' \
    "$(date --iso-8601=seconds)" \
    > "$STATE_FILE"

  chmod 600 "$STATE_FILE"
  exit 0
fi

PROBLEM_LINES="$(
  grep -E '^\[(WARNING|CRITICAL)\]' "$OUTPUT_FILE" ||
  true
)"

if [ -z "$PROBLEM_LINES" ]; then
  PROBLEM_LINES="$(
    tail -n 20 "$OUTPUT_FILE"
  )"
fi

PROBLEM_LINES="$(
  printf '%s\n' "$PROBLEM_LINES" |
    head -c 2800
)"

CURRENT_FINGERPRINT="$(
  printf '%s\n%s\n' \
    "$CURRENT_LEVEL" \
    "$PROBLEM_LINES" |
    sha256sum |
    awk '{print $1}'
)"

if [ "$CURRENT_LEVEL" != "$PREVIOUS_LEVEL" ] ||
   [ "$CURRENT_FINGERPRINT" != "$PREVIOUS_FINGERPRINT" ]; then

  ALERT_MESSAGE="$(
    printf 'Server health problem detected.\nHost: %s\nTime: %s\nResult: %s\n\n%s\n\nLog: journalctl -u ai-prof-health.service' \
      "$(hostname)" \
      "$(date --iso-8601=seconds)" \
      "$CURRENT_LEVEL" \
      "$PROBLEM_LINES"
  )"

  if ! "$ALERT_SCRIPT" "$CURRENT_LEVEL" "$ALERT_MESSAGE"; then
    echo "ERROR: Health notification could not be delivered." >&2
  fi
else
  echo "Telegram alert suppressed: the problem has not changed."
fi

printf '%s|%s|%s\n' \
  "$CURRENT_LEVEL" \
  "$CURRENT_FINGERPRINT" \
  "$(date --iso-8601=seconds)" \
  > "$STATE_FILE"

chmod 600 "$STATE_FILE"

if [ "$HEALTH_EXIT_CODE" -eq 1 ]; then
  exit 1
fi

exit 2

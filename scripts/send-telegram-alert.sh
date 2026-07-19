#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

STACK_DIR="/home/agent/ai-prof-stack"
TOKEN_FILE="$STACK_DIR/secrets/telegram_bot_token"
CHAT_FILE="$STACK_DIR/secrets/telegram_chat_id"

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 LEVEL MESSAGE" >&2
  exit 64
fi

LEVEL="$1"
shift
MESSAGE="$*"

case "$LEVEL" in
  TEST|INFO|WARNING|CRITICAL|RECOVERY)
    ;;
  *)
    echo "ERROR: Unsupported alert level: $LEVEL" >&2
    exit 64
    ;;
esac

if [ ! -s "$TOKEN_FILE" ]; then
  echo "ERROR: Telegram bot token file is missing or empty." >&2
  exit 1
fi

if [ ! -s "$CHAT_FILE" ]; then
  echo "ERROR: Telegram chat ID file is missing or empty." >&2
  exit 1
fi

if [ "$(stat -c '%a' "$TOKEN_FILE")" != "600" ]; then
  echo "ERROR: Telegram token file permissions must be 600." >&2
  exit 1
fi

if [ "$(stat -c '%a' "$CHAT_FILE")" != "600" ]; then
  echo "ERROR: Telegram chat ID file permissions must be 600." >&2
  exit 1
fi

TELEGRAM_BOT_TOKEN="$(cat "$TOKEN_FILE")"
TELEGRAM_CHAT_ID="$(cat "$CHAT_FILE")"

FULL_MESSAGE="[$LEVEL] AI PROF

$MESSAGE"

RESPONSE="$(
  curl \
    --silent \
    --show-error \
    --fail \
    --max-time 20 \
    --retry 2 \
    --retry-delay 2 \
    --request POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$FULL_MESSAGE" \
    --data-urlencode "disable_web_page_preview=true"
)"

if ! jq -e \
  '.ok == true and .result.message_id != null' \
  >/dev/null \
  <<<"$RESPONSE"
then
  echo "ERROR: Telegram did not confirm message delivery." >&2
  unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID RESPONSE
  exit 1
fi

unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID RESPONSE

echo "Telegram alert delivered: $LEVEL"

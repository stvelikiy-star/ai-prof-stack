#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

STACK_DIR="/home/agent/ai-prof-stack"
TOKEN_FILE="$STACK_DIR/secrets/telegram_bot_token"

read -r -s -p "Paste Telegram bot token: " TELEGRAM_BOT_TOKEN
printf '\n'

if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
  echo "ERROR: Telegram bot token is empty." >&2
  exit 1
fi

BOT_RESPONSE="$(
  curl \
    --silent \
    --show-error \
    --fail \
    --max-time 20 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
)"

if ! jq -e \
  '.ok == true and .result.is_bot == true' \
  >/dev/null \
  <<<"$BOT_RESPONSE"
then
  echo "ERROR: Telegram rejected the bot token." >&2
  unset TELEGRAM_BOT_TOKEN BOT_RESPONSE
  exit 1
fi

BOT_USERNAME="$(
  jq -r '.result.username' <<<"$BOT_RESPONSE"
)"

BOT_NAME="$(
  jq -r '.result.first_name' <<<"$BOT_RESPONSE"
)"

install \
  --mode=600 \
  /dev/null \
  "$TOKEN_FILE"

printf '%s\n' "$TELEGRAM_BOT_TOKEN" > "$TOKEN_FILE"

unset TELEGRAM_BOT_TOKEN BOT_RESPONSE

echo "Telegram bot validated: $BOT_NAME (@$BOT_USERNAME)"
echo "Token file created: $TOKEN_FILE"
stat -c 'Permissions: %a' "$TOKEN_FILE"
echo "TELEGRAM TOKEN SETUP: PASS"

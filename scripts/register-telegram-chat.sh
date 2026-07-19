#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

STACK_DIR="/home/agent/ai-prof-stack"
TOKEN_FILE="$STACK_DIR/secrets/telegram_bot_token"
CHAT_FILE="$STACK_DIR/secrets/telegram_chat_id"

if [ ! -s "$TOKEN_FILE" ]; then
  echo "ERROR: Telegram bot token file is missing or empty." >&2
  exit 1
fi

TOKEN_PERMISSIONS="$(stat -c '%a' "$TOKEN_FILE")"

if [ "$TOKEN_PERMISSIONS" != "600" ]; then
  echo "ERROR: Telegram token file permissions must be 600." >&2
  exit 1
fi

TELEGRAM_BOT_TOKEN="$(cat "$TOKEN_FILE")"

BOT_RESPONSE="$(
  curl \
    --silent \
    --show-error \
    --fail \
    --max-time 20 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
)"

if ! jq -e '.ok == true and .result.is_bot == true' \
  >/dev/null <<<"$BOT_RESPONSE"
then
  echo "ERROR: Telegram bot validation failed." >&2
  unset TELEGRAM_BOT_TOKEN BOT_RESPONSE
  exit 1
fi

BOT_USERNAME="$(jq -r '.result.username' <<<"$BOT_RESPONSE")"
BOT_NAME="$(jq -r '.result.first_name' <<<"$BOT_RESPONSE")"

WEBHOOK_RESPONSE="$(
  curl \
    --silent \
    --show-error \
    --fail \
    --max-time 20 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
)"

WEBHOOK_URL="$(jq -r '.result.url // ""' <<<"$WEBHOOK_RESPONSE")"

if [ -n "$WEBHOOK_URL" ]; then
  echo "ERROR: An active Telegram webhook already exists." >&2
  echo "The webhook was not changed."
  unset TELEGRAM_BOT_TOKEN BOT_RESPONSE WEBHOOK_RESPONSE
  exit 1
fi

echo "Telegram bot: $BOT_NAME (@$BOT_USERNAME)"
echo
echo "Open the private Telegram group AI PROF Control."
echo "Send this exact command:"
echo
echo "/register@$BOT_USERNAME"
echo

read -r -p "After sending the command, press Enter here: " _

UPDATES_RESPONSE="$(
  curl \
    --silent \
    --show-error \
    --fail \
    --max-time 40 \
    --request POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
    --data-urlencode "timeout=30" \
    --data-urlencode 'allowed_updates=["message"]'
)"

REGISTRATION_UPDATE="$(
  jq \
    --compact-output \
    --arg expected_command "/register@$BOT_USERNAME" \
    '
      [
        .result[]
        | select(.message? != null)
        | select(
            .message.chat.type == "group"
            or .message.chat.type == "supergroup"
          )
        | select((.message.text // "") == $expected_command)
      ]
      | last // empty
    ' <<<"$UPDATES_RESPONSE"
)"

if [ -z "$REGISTRATION_UPDATE" ]; then
  echo "ERROR: The registration command was not found." >&2
  echo "Confirm that the bot is a member of the group and rerun this script."
  unset TELEGRAM_BOT_TOKEN BOT_RESPONSE WEBHOOK_RESPONSE UPDATES_RESPONSE
  exit 1
fi

TELEGRAM_CHAT_ID="$(
  jq -r '.message.chat.id' <<<"$REGISTRATION_UPDATE"
)"

TELEGRAM_CHAT_TITLE="$(
  jq -r '.message.chat.title // "Unnamed Telegram group"' \
    <<<"$REGISTRATION_UPDATE"
)"

install \
  --mode=600 \
  /dev/null \
  "$CHAT_FILE"

printf '%s\n' "$TELEGRAM_CHAT_ID" > "$CHAT_FILE"

TEST_MESSAGE="AI PROF server connection test: PASS
Host: $(hostname)
Time: $(date --iso-8601=seconds)
PostgreSQL: $(docker inspect --format='{{.State.Health.Status}}' ai-prof-postgres)
n8n: $(docker inspect --format='{{.State.Health.Status}}' ai-prof-n8n)"

SEND_RESPONSE="$(
  curl \
    --silent \
    --show-error \
    --fail \
    --max-time 20 \
    --request POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$TEST_MESSAGE"
)"

if ! jq -e '.ok == true and .result.message_id != null' \
  >/dev/null <<<"$SEND_RESPONSE"
then
  echo "ERROR: Telegram test message was not delivered." >&2
  unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
  exit 1
fi

unset \
  TELEGRAM_BOT_TOKEN \
  TELEGRAM_CHAT_ID \
  BOT_RESPONSE \
  WEBHOOK_RESPONSE \
  UPDATES_RESPONSE \
  SEND_RESPONSE

echo
echo "Telegram group validated: $TELEGRAM_CHAT_TITLE"
echo "Chat ID file created: $CHAT_FILE"
stat -c 'Permissions: %a' "$CHAT_FILE"
echo "Telegram test message delivered."
echo "TELEGRAM GROUP SETUP: PASS"

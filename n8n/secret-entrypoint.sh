#!/bin/sh

set -eu

DB_POSTGRESDB_PASSWORD="$(
  tr -d '\r\n' < /run/secrets/postgres_n8n_password
)"

N8N_ENCRYPTION_KEY="$(
  tr -d '\r\n' < /run/secrets/n8n_encryption_key
)"

if [ -z "$DB_POSTGRESDB_PASSWORD" ]; then
  echo "ERROR: The n8n database password secret is empty." >&2
  exit 1
fi

if [ -z "$N8N_ENCRYPTION_KEY" ]; then
  echo "ERROR: The n8n encryption key secret is empty." >&2
  exit 1
fi

export DB_POSTGRESDB_PASSWORD
export N8N_ENCRYPTION_KEY

exec /docker-entrypoint.sh "$@"

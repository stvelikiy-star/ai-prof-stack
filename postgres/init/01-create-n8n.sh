#!/usr/bin/env bash

set -Eeuo pipefail

N8N_DB_PASSWORD="$(tr -d '\r\n' < /run/secrets/postgres_n8n_password)"

if [[ -z "$N8N_DB_PASSWORD" ]]; then
  echo "ERROR: The n8n database password secret is empty." >&2
  exit 1
fi

psql \
  --variable=ON_ERROR_STOP=1 \
  --username="$POSTGRES_USER" \
  --dbname="$POSTGRES_DB" \
  --set=n8n_password="$N8N_DB_PASSWORD" <<'EOSQL'
CREATE ROLE n8n
  WITH LOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION
  PASSWORD :'n8n_password';

CREATE DATABASE n8n
  WITH OWNER = n8n
  ENCODING = 'UTF8'
  TEMPLATE = template0;

REVOKE ALL ON DATABASE n8n FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE n8n TO n8n;
EOSQL

unset N8N_DB_PASSWORD

echo "The n8n PostgreSQL database and application role were created successfully."

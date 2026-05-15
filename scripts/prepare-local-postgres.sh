#!/usr/bin/env sh
set -eu

: "${TALK_LOCAL_POSTGRES_HOST:=127.0.0.1}"
: "${TALK_LOCAL_POSTGRES_PORT:=5432}"
: "${TALK_ZITADEL_DATABASE_NAME:=t_zitadel}"

createdb -h "$TALK_LOCAL_POSTGRES_HOST" -p "$TALK_LOCAL_POSTGRES_PORT" t_authz 2>/dev/null || true
createdb -h "$TALK_LOCAL_POSTGRES_HOST" -p "$TALK_LOCAL_POSTGRES_PORT" "$TALK_ZITADEL_DATABASE_NAME" 2>/dev/null || true

echo "local Postgres databases are ready: t_authz, $TALK_ZITADEL_DATABASE_NAME"

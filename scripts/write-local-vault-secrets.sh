#!/usr/bin/env sh
set -eu

: "${TALK_LOCAL_POSTGRES_HOST:=talk-host-postgres.talk-local.svc.cluster.local}"
: "${TALK_LOCAL_POSTGRES_PORT:=5432}"
: "${TALK_LOCAL_POSTGRES_USER:=$(id -un)}"
: "${TALK_AUTHZ_DATABASE_URL:=postgresql+psycopg://$TALK_LOCAL_POSTGRES_USER@$TALK_LOCAL_POSTGRES_HOST:$TALK_LOCAL_POSTGRES_PORT/t_authz}"
: "${TALK_ZITADEL_DATABASE_NAME:=t_zitadel}"
: "${TALK_ZITADEL_DATABASE_DSN:=postgresql://$TALK_LOCAL_POSTGRES_USER@$TALK_LOCAL_POSTGRES_HOST:$TALK_LOCAL_POSTGRES_PORT/$TALK_ZITADEL_DATABASE_NAME?sslmode=disable}"
: "${TALK_ZITADEL_MASTERKEY:=LocalDevZitadelMasterkey00000000}"
: "${TALK_ZITADEL_ADMIN_PASSWORD:=Password1!}"
: "${TALK_ZITADEL_WEBHOOK_SIGNING_KEY:=local-webhook-signing-key}"
: "${TALK_ZITADEL_ISSUER:=http://zitadel.localhost}"
: "${TALK_ZITADEL_CLIENT_ID:=local-placeholder-client-id}"
: "${TALK_ZITADEL_CLIENT_SECRET:=local-placeholder-client-secret}"
: "${TALK_OAUTH2_PROXY_ISSUER_URL:=http://zitadel.localhost}"
: "${TALK_OAUTH2_PROXY_INSECURE_SKIP_ISSUER_VERIFICATION:=false}"
: "${TALK_OAUTH2_PROXY_COOKIE_SECRET:=LocalDevOauth2ProxyCookieSecretX}"
: "${TALK_OAUTH2_PROXY_REDIRECT_URL:=http://talk.localhost/oauth2/callback}"
: "${TALK_OAUTH2_PROXY_COOKIE_DOMAIN:=talk.localhost}"
: "${TALK_OAUTH2_PROXY_WHITELIST_DOMAIN:=.localhost}"
: "${TALK_OAUTH2_PROXY_COOKIE_SECURE:=false}"
: "${TALK_CONSOLE_API_ZITADEL_BASE_URL:=http://zitadel.localhost}"
: "${TALK_CONSOLE_API_ZITADEL_ADMIN_TOKEN:=local-placeholder-admin-token}"
: "${TALK_CONSOLE_API_ZITADEL_API_HOST_HEADER:=}"
: "${TALK_CONSOLE_API_ZITADEL_PROJECT_ID:=local-placeholder-project-id}"
: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"

put_secret() {
  path=$1
  shift
  python3 - "$@" <<'PY' | curl --fail --silent --show-error \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request POST \
    --data-binary @- \
    "${VAULT_ADDR}/v1/secret/data/${path}" >/dev/null
import json
import sys

values = {}
for item in sys.argv[1:]:
    key, value = item.split("=", 1)
    values[key] = value
print(json.dumps({"data": values}))
PY
}

put_secret "talk/local/authz/database" \
  "database-url=$TALK_AUTHZ_DATABASE_URL"

put_secret "talk/local/zitadel/config" \
  "masterkey=$TALK_ZITADEL_MASTERKEY" \
  "database-dsn=$TALK_ZITADEL_DATABASE_DSN" \
  "database-host=$TALK_LOCAL_POSTGRES_HOST" \
  "database-port=$TALK_LOCAL_POSTGRES_PORT" \
  "database-name=$TALK_ZITADEL_DATABASE_NAME" \
  "database-user=$TALK_LOCAL_POSTGRES_USER" \
  "admin-password=$TALK_ZITADEL_ADMIN_PASSWORD"

put_secret "talk/local/identity-sync/zitadel-webhook" \
  "signing-key=$TALK_ZITADEL_WEBHOOK_SIGNING_KEY"

put_secret "talk/local/oauth2-proxy/oidc" \
  "issuer-url=$TALK_OAUTH2_PROXY_ISSUER_URL" \
  "client-id=$TALK_ZITADEL_CLIENT_ID" \
  "client-secret=$TALK_ZITADEL_CLIENT_SECRET" \
  "cookie-secret=$TALK_OAUTH2_PROXY_COOKIE_SECRET" \
  "redirect-url=$TALK_OAUTH2_PROXY_REDIRECT_URL" \
  "cookie-domain=$TALK_OAUTH2_PROXY_COOKIE_DOMAIN" \
  "whitelist-domain=$TALK_OAUTH2_PROXY_WHITELIST_DOMAIN" \
  "cookie-secure=$TALK_OAUTH2_PROXY_COOKIE_SECURE" \
  "insecure-skip-issuer-verification=$TALK_OAUTH2_PROXY_INSECURE_SKIP_ISSUER_VERIFICATION"

put_secret "talk/local/console-api/zitadel-admin" \
  "base-url=$TALK_CONSOLE_API_ZITADEL_BASE_URL" \
  "admin-token=$TALK_CONSOLE_API_ZITADEL_ADMIN_TOKEN" \
  "api-host-header=$TALK_CONSOLE_API_ZITADEL_API_HOST_HEADER" \
  "project-id=$TALK_CONSOLE_API_ZITADEL_PROJECT_ID"

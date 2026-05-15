#!/usr/bin/env bash
set -euo pipefail

# Populates Azure Key Vault with the initial set of secrets needed by
# the dev environment. Run this after Terraform has created the Key Vault
# and before deploying any workloads.
#
# Some secrets (Zitadel client-id, client-secret, project-id, admin-token)
# are populated with placeholder values here and must be updated after
# Zitadel is running and provisioned with provision-zitadel-management.py.
#
# Usage:
#   export TALK_KEY_VAULT_NAME="talk-dev-kv"
#   export TALK_POSTGRES_FQDN="talk-dev-pg.postgres.database.azure.com"
#   export TALK_POSTGRES_ADMIN_USER="talkadmin"
#   export TALK_POSTGRES_ADMIN_PASSWORD="<password>"
#   ./scripts/populate-keyvault-secrets.sh

TALK_KEY_VAULT_NAME="${TALK_KEY_VAULT_NAME:?Set TALK_KEY_VAULT_NAME}"
TALK_POSTGRES_FQDN="${TALK_POSTGRES_FQDN:?Set TALK_POSTGRES_FQDN}"
TALK_POSTGRES_ADMIN_USER="${TALK_POSTGRES_ADMIN_USER:?Set TALK_POSTGRES_ADMIN_USER}"
TALK_POSTGRES_ADMIN_PASSWORD="${TALK_POSTGRES_ADMIN_PASSWORD:?Set TALK_POSTGRES_ADMIN_PASSWORD}"
TALK_PUBLIC_HOST="${TALK_PUBLIC_HOST:-talk.dev.telodev.com}"
TALK_ZITADEL_HOST="${TALK_ZITADEL_HOST:-zitadel.dev.telodev.com}"

ZITADEL_MASTERKEY="${TALK_ZITADEL_MASTERKEY:-$(openssl rand -hex 16)}"
ZITADEL_ADMIN_PASSWORD="${TALK_ZITADEL_ADMIN_PASSWORD:-$(openssl rand -base64 24)}"
OAUTH2_COOKIE_SECRET="${TALK_OAUTH2_COOKIE_SECRET:-$(openssl rand -hex 16)}"
WEBHOOK_SIGNING_KEY="${TALK_WEBHOOK_SIGNING_KEY:-$(openssl rand -base64 32)}"

PG_DSN="postgresql://${TALK_POSTGRES_ADMIN_USER}:${TALK_POSTGRES_ADMIN_PASSWORD}@${TALK_POSTGRES_FQDN}:5432/t_zitadel?sslmode=require"
AUTHZ_DB_URL="postgresql+psycopg://${TALK_POSTGRES_ADMIN_USER}:${TALK_POSTGRES_ADMIN_PASSWORD}@${TALK_POSTGRES_FQDN}:5432/t_authz?sslmode=require"

set_secret() {
  az keyvault secret set \
    --vault-name "$TALK_KEY_VAULT_NAME" \
    --name "$1" \
    --value "$2" \
    --output none
  echo "  set $1"
}

echo "==> Populating Key Vault: $TALK_KEY_VAULT_NAME"

# Zitadel database + config
set_secret "talk-dev-zitadel-masterkey"       "$ZITADEL_MASTERKEY"
set_secret "talk-dev-zitadel-database-dsn"    "$PG_DSN"
set_secret "talk-dev-zitadel-database-host"   "$TALK_POSTGRES_FQDN"
set_secret "talk-dev-zitadel-database-port"   "5432"
set_secret "talk-dev-zitadel-database-name"   "t_zitadel"
set_secret "talk-dev-zitadel-database-user"   "$TALK_POSTGRES_ADMIN_USER"
set_secret "talk-dev-zitadel-admin-password"  "$ZITADEL_ADMIN_PASSWORD"

# Authz database
set_secret "talk-dev-authz-database-url" "$AUTHZ_DB_URL"

# Identity webhook
set_secret "talk-dev-identity-sync-zitadel-webhook-signing-key" "$WEBHOOK_SIGNING_KEY"

# Zitadel issuer / admin (placeholders until Zitadel is provisioned)
set_secret "talk-dev-zitadel-issuer-url"       "https://${TALK_ZITADEL_HOST}"
set_secret "talk-dev-zitadel-admin-token"      "PLACEHOLDER_RUN_PROVISION_SCRIPT"
set_secret "talk-dev-zitadel-api-host-header"  "$TALK_ZITADEL_HOST"
set_secret "talk-dev-zitadel-project-id"       "PLACEHOLDER_RUN_PROVISION_SCRIPT"

# oauth2-proxy
set_secret "talk-dev-oauth2-proxy-client-id"                         "PLACEHOLDER_RUN_PROVISION_SCRIPT"
set_secret "talk-dev-oauth2-proxy-client-secret"                     "PLACEHOLDER_RUN_PROVISION_SCRIPT"
set_secret "talk-dev-oauth2-proxy-cookie-secret"                     "$OAUTH2_COOKIE_SECRET"
set_secret "talk-dev-oauth2-proxy-redirect-url"                      "https://${TALK_PUBLIC_HOST}/oauth2/callback"
set_secret "talk-dev-oauth2-proxy-cookie-domain"                     "$TALK_PUBLIC_HOST"
set_secret "talk-dev-oauth2-proxy-whitelist-domain"                  ".${TALK_PUBLIC_HOST}"
set_secret "talk-dev-oauth2-proxy-cookie-secure"                     "true"
set_secret "talk-dev-oauth2-proxy-insecure-skip-issuer-verification" "false"

echo ""
echo "==> Done. Generated secrets printed below (save securely, not shown again):"
echo "    Zitadel masterkey:       $ZITADEL_MASTERKEY"
echo "    Zitadel admin password:  $ZITADEL_ADMIN_PASSWORD"
echo "    oauth2-proxy cookie:     $OAUTH2_COOKIE_SECRET"
echo "    Webhook signing key:     $WEBHOOK_SIGNING_KEY"
echo ""
echo "After Zitadel is running, run provision-zitadel-management.py and update:"
echo "  talk-dev-zitadel-admin-token"
echo "  talk-dev-zitadel-project-id"
echo "  talk-dev-oauth2-proxy-client-id"
echo "  talk-dev-oauth2-proxy-client-secret"

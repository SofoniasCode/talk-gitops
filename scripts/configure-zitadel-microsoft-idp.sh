#!/usr/bin/env bash
set -euo pipefail

# Configures Microsoft (Entra ID) as an external identity provider in Zitadel.
#
# Uses Zitadel's native Azure AD provider (/management/v1/idps/azure) which
# handles multi-tenant issuer validation correctly, allowing users from ANY
# Microsoft/Azure AD tenant to log in.
#
# The Entra ID app registration (entra-idp.tf) must have:
#   - sign_in_audience = "AzureADandPersonalMicrosoftAccount"
#   - Optional claims: email, preferred_username, given_name, family_name
#
# Prerequisites:
#   - Zitadel is running and accessible
#   - Terraform has created the Entra ID app registration and stored
#     the client ID/secret in Key Vault
#   - The admin service account PAT is available (from Zitadel first boot)
#
# Usage:
#   export ZITADEL_DOMAIN="zitadel.dev.telodev.com"
#   export ZITADEL_PAT="<admin-service-pat>"
#   export MICROSOFT_CLIENT_ID="<from terraform output>"
#   export MICROSOFT_CLIENT_SECRET="<from key vault>"
#   ./scripts/configure-zitadel-microsoft-idp.sh
#
# If Zitadel is only accessible via port-forward, set ZITADEL_API_URL:
#   export ZITADEL_API_URL="http://localhost:8090"

ZITADEL_DOMAIN="${ZITADEL_DOMAIN:?Set ZITADEL_DOMAIN (e.g. zitadel.dev.telodev.com)}"
ZITADEL_PAT="${ZITADEL_PAT:?Set ZITADEL_PAT (admin service account PAT)}"
MICROSOFT_CLIENT_ID="${MICROSOFT_CLIENT_ID:?Set MICROSOFT_CLIENT_ID}"
MICROSOFT_CLIENT_SECRET="${MICROSOFT_CLIENT_SECRET:?Set MICROSOFT_CLIENT_SECRET}"

ZITADEL_API_URL="${ZITADEL_API_URL:-https://${ZITADEL_DOMAIN}}"

echo "==> Configuring Microsoft IdP in Zitadel (native Azure AD provider)"
echo "    API: ${ZITADEL_API_URL}"
echo "    Domain: ${ZITADEL_DOMAIN}"

zitadel_curl() {
  curl -s "$@" \
    -H "Authorization: Bearer ${ZITADEL_PAT}" \
    -H "Host: ${ZITADEL_DOMAIN}" \
    -H "Content-Type: application/json"
}

# ---------- clean up any existing Microsoft IdP (instance-level v1) ----------
EXISTING_ADMIN=$(zitadel_curl "${ZITADEL_API_URL}/admin/v1/idps/_search" \
  -d '{"queries":[]}' | python3 -c "
import json, sys
data = json.load(sys.stdin)
for idp in data.get('result', []):
    if idp.get('name', '') == 'Microsoft':
        print(idp['id'])
        break
" 2>/dev/null || true)

if [ -n "${EXISTING_ADMIN}" ]; then
  echo "    Removing old instance-level Microsoft IdP (ID: ${EXISTING_ADMIN})..."
  zitadel_curl -o /dev/null "${ZITADEL_API_URL}/admin/v1/policies/login/idps/${EXISTING_ADMIN}" -X DELETE 2>/dev/null || true
  zitadel_curl -X DELETE "${ZITADEL_API_URL}/admin/v1/idps/${EXISTING_ADMIN}" > /dev/null
  sleep 2
fi

# ---------- clean up any existing Microsoft IdP (org-level) ----------
for IDP_ID in $(zitadel_curl "${ZITADEL_API_URL}/management/v1/idps/_search" \
  -d '{"queries":[]}' | python3 -c "
import json, sys
data = json.load(sys.stdin)
for idp in data.get('result', []):
    if idp.get('name', '') == 'Microsoft':
        print(idp['id'])
" 2>/dev/null); do
  echo "    Removing old org-level Microsoft IdP (ID: ${IDP_ID})..."
  zitadel_curl -o /dev/null "${ZITADEL_API_URL}/management/v1/policies/login/idps/${IDP_ID}" -X DELETE 2>/dev/null || true
  zitadel_curl -X DELETE "${ZITADEL_API_URL}/management/v1/idps/${IDP_ID}" > /dev/null
  sleep 2
done

# ---------- create native Azure AD provider (multi-tenant) ----------
# Empty tenant object = "common" = any Azure AD or personal Microsoft account.
RESPONSE=$(zitadel_curl -w "\n%{http_code}" "${ZITADEL_API_URL}/management/v1/idps/azure" \
  -d "{
    \"name\": \"Microsoft\",
    \"clientId\": \"${MICROSOFT_CLIENT_ID}\",
    \"clientSecret\": \"${MICROSOFT_CLIENT_SECRET}\",
    \"tenant\": {},
    \"emailVerified\": true,
    \"scopes\": [\"openid\", \"profile\", \"email\", \"User.Read\"],
    \"providerOptions\": {
      \"isLinkingAllowed\": true,
      \"isCreationAllowed\": true,
      \"isAutoCreation\": true,
      \"isAutoUpdate\": true,
      \"autoLinking\": 2
    }
  }")

HTTP_CODE=$(echo "${RESPONSE}" | tail -1)
BODY=$(echo "${RESPONSE}" | sed '$d')

if [ "${HTTP_CODE}" -lt 200 ] || [ "${HTTP_CODE}" -ge 300 ]; then
  echo "    ERROR: Failed to create Microsoft IdP (HTTP ${HTTP_CODE})"
  echo "    Response: ${BODY}"
  exit 1
fi

IDP_ID=$(echo "${BODY}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
echo "    Created Microsoft IdP (ID: ${IDP_ID})"

# ---------- ensure org-level login policy exists ----------
zitadel_curl -o /dev/null "${ZITADEL_API_URL}/management/v1/policies/login" \
  -d '{
    "allowUsernamePassword": true,
    "allowRegister": true,
    "allowExternalIdp": true,
    "passwordlessType": 1,
    "allowDomainDiscovery": true
  }' 2>/dev/null || true

# ---------- add IdP to the org login policy ----------
zitadel_curl -o /dev/null "${ZITADEL_API_URL}/management/v1/policies/login/idps" \
  -d "{\"idpId\": \"${IDP_ID}\", \"ownerType\": 2}"
echo "    Added Microsoft IdP to login policy"

echo ""
echo "==> Done. Microsoft login is now available for any Microsoft account."

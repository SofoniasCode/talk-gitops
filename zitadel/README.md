# Zitadel Setup

This runbook turns the management-plane identity contract into real Zitadel configuration.

Official docs used:

- OIDC login apps: https://zitadel.com/docs/guides/integrate/login/oidc/login-users
- Project roles: https://zitadel.com/docs/guides/manage/console/roles
- Role claims: https://zitadel.com/docs/guides/integrate/retrieve-user-roles
- Reserved scopes: https://zitadel.com/docs/apis/openidoauth/scopes
- Token actions: https://zitadel.com/docs/apis/actions/complement-token
- Action code examples: https://zitadel.com/docs/apis/actions/code-examples
- Webhook targets/signing: https://zitadel.com/docs/guides/integrate/actions/usage
- Signature verification: https://zitadel.com/docs/guides/integrate/actions/testing-request-signature

## Dev Project

Create one Zitadel project for Talk management, for example `Talk Management`.

Create these project roles. The role keys must match `authz` role ids exactly:

- `organization.viewer`
- `organization.admin`
- `organization.owner`
- `citadel.viewer`
- `citadel.operator`
- `citadel.admin`

Assign staff users one of the `citadel.*` roles. Assign customer users one of the
`organization.*` roles in their organization context.

## OIDC Application

Create a web OIDC application in the Talk management project for `oauth2-proxy`.

Required settings:

- Use authorization code flow.
- Use a confidential client with client secret, because `oauth2-proxy` stores the client secret in Key Vault or Vault.
- Register redirect URIs for the public gateway host, for example `https://<public-gateway-host>/oauth2/callback`.
- Include post-logout redirect URIs for the public dev gateway host.
- Request `openid`, `profile`, `email`, and `urn:zitadel:iam:user:resourceowner` scopes.
- Enable project role assertion and OIDC application role/userinfo assertions. The provisioning
  script enforces these settings on both newly created and existing apps.

For local development, use `http://talk.localhost/oauth2/callback` and enable Zitadel dev mode for
the local OIDC application.

## Talk Claims

`oauth2-proxy` forwards identity through `X-Talk-*` headers. Zitadel's native project role claim is
nested by project and organization, so Talk uses a small token action to emit flat claims:

```text
urn:talk:roles = ["organization.viewer", "organization.owner"]
urn:talk:organization_id = "<zitadel-organization-id>"
```

Create a Zitadel Action from `zitadel/actions/talk_roles_claim.js` and attach it to both
Complement Token triggers:

- Pre Userinfo creation
- Pre access token creation

## Provisioning Script

Use `scripts/provision-zitadel-management.py` to create the Talk management project, roles,
`oauth2-proxy` OIDC application, and token-claim action through the Zitadel APIs.

The script authenticates with a Zitadel admin Personal Access Token. For clean local installs,
the Kubernetes deployment writes this token to `/zitadel/bootstrap/admin-service.pat`, and the
script reads it automatically through `kubectl`. For cloud or manual runs, set
`TALK_ZITADEL_ADMIN_PAT`.

Local dev:

```sh
scripts/provision-zitadel-management.py --write-local-vault --sync-local-k8s
```

Useful overrides:

```sh
export TALK_ZITADEL_ISSUER="http://zitadel.localhost"
# Optional when the local shell cannot resolve zitadel.localhost but the Envoy NodePort is available:
export TALK_ZITADEL_API_URL="http://127.0.0.1:30080"
export TALK_ZITADEL_API_HOST_HEADER="zitadel.localhost"
export TALK_ZITADEL_ORGANIZATION_NAME="ZITADEL"
export TALK_ZITADEL_PROJECT_NAME="Talk Management"
export TALK_ZITADEL_OAUTH2_PROXY_APP_NAME="oauth2-proxy-local"
export TALK_ZITADEL_REDIRECT_URIS="http://talk.localhost/oauth2/callback"
export TALK_ZITADEL_POST_LOGOUT_URIS="http://talk.localhost/"
# Use this after a partial provisioning run if the app exists but Vault has no real secret yet:
export TALK_ZITADEL_REGENERATE_CLIENT_SECRET="true"
```

For Azure, copy `zitadel/azure-dev.env.example`, set the issuer, organization ID/name, redirect URI,
and `TALK_ZITADEL_ADMIN_PAT`, then write the returned client values to Azure Key Vault using the
secret names below.

Zitadel returns an OIDC client secret when a new app is created or when
`TALK_ZITADEL_REGENERATE_CLIENT_SECRET=true` is set. On ordinary reruns, the script keeps the
existing local Vault `client-secret` value.

## Identity Webhook Target

Create a Zitadel Actions v2 REST webhook target for identity events:

```text
https://<public-gateway-host>/identity-sync/v1/webhooks/zitadel
```

Use JSON payloads. Store the returned target signing key in Azure Key Vault as:

```text
talk-dev-identity-sync-zitadel-webhook-signing-key
```

`identity-sync` validates the official `ZITADEL-Signature` header using that signing key.

Set event executions for the identity events that should update the projection. Start with:

- user created/changed/deleted events
- organization created/changed/deleted events
- user grant or authorization changed events

Keep the event list narrow at first, then add more mappings as `identity-sync` learns them.

## Secret Store Values

Azure dev GitOps overlays expect these Azure Key Vault secrets:

```text
talk-dev-authz-database-url
talk-dev-identity-sync-zitadel-webhook-signing-key
talk-dev-zitadel-issuer-url
talk-dev-zitadel-admin-token
talk-dev-zitadel-api-host-header
talk-dev-zitadel-project-id
talk-dev-oauth2-proxy-client-id
talk-dev-oauth2-proxy-client-secret
talk-dev-oauth2-proxy-cookie-secret
talk-dev-oauth2-proxy-redirect-url
talk-dev-oauth2-proxy-cookie-domain
talk-dev-oauth2-proxy-whitelist-domain
talk-dev-oauth2-proxy-cookie-secure
talk-dev-oauth2-proxy-insecure-skip-issuer-verification
```

Write the oauth2-proxy values to Key Vault:

```sh
az keyvault secret set \
  --vault-name "$TALK_KEY_VAULT_NAME" \
  --name talk-dev-zitadel-issuer-url \
  --value "https://<zitadel-dev-domain>"
az keyvault secret set \
  --vault-name "$TALK_KEY_VAULT_NAME" \
  --name talk-dev-oauth2-proxy-client-id \
  --value "<zitadel-client-id>"
az keyvault secret set \
  --vault-name "$TALK_KEY_VAULT_NAME" \
  --name talk-dev-oauth2-proxy-client-secret \
  --value "<zitadel-client-secret>"
az keyvault secret set \
  --vault-name "$TALK_KEY_VAULT_NAME" \
  --name talk-dev-oauth2-proxy-cookie-secret \
  --value "<32-byte-random-cookie-secret>"
az keyvault secret set \
  --vault-name "$TALK_KEY_VAULT_NAME" \
  --name talk-dev-oauth2-proxy-redirect-url \
  --value "https://<public-gateway-host>/oauth2/callback"
az keyvault secret set \
  --vault-name "$TALK_KEY_VAULT_NAME" \
  --name talk-dev-oauth2-proxy-cookie-domain \
  --value "<public-gateway-host>"
az keyvault secret set \
  --vault-name "$TALK_KEY_VAULT_NAME" \
  --name talk-dev-oauth2-proxy-whitelist-domain \
  --value ".<public-gateway-host>"
az keyvault secret set \
  --vault-name "$TALK_KEY_VAULT_NAME" \
  --name talk-dev-oauth2-proxy-cookie-secure \
  --value "true"
az keyvault secret set \
  --vault-name "$TALK_KEY_VAULT_NAME" \
  --name talk-dev-oauth2-proxy-insecure-skip-issuer-verification \
  --value "false"
```

The same naming pattern applies to `stg` and `prod`.

Local dev runs Zitadel in Kubernetes, uses your existing localhost Postgres, and stores runtime
secrets in HashiCorp Vault KV v2:

```text
secret/talk/local/authz/database database-url=<postgres-url>
secret/talk/local/zitadel/config masterkey=<32-character-masterkey>
secret/talk/local/zitadel/config database-dsn=<postgres-dsn>
secret/talk/local/zitadel/config database-host=<postgres-host>
secret/talk/local/zitadel/config database-port=<postgres-port>
secret/talk/local/zitadel/config database-name=t_zitadel
secret/talk/local/zitadel/config database-user=<postgres-user>
secret/talk/local/zitadel/config admin-password=<initial-admin-password>
secret/talk/local/identity-sync/zitadel-webhook signing-key=<zitadel-target-signing-key>
secret/talk/local/console-api/zitadel-admin base-url=http://zitadel.localhost
secret/talk/local/console-api/zitadel-admin admin-token=<zitadel-admin-token>
secret/talk/local/console-api/zitadel-admin api-host-header=
secret/talk/local/console-api/zitadel-admin project-id=<talk-management-project-id>
secret/talk/local/oauth2-proxy/oidc issuer-url=http://zitadel.localhost
secret/talk/local/oauth2-proxy/oidc client-id=<zitadel-client-id>
secret/talk/local/oauth2-proxy/oidc client-secret=<zitadel-client-secret>
secret/talk/local/oauth2-proxy/oidc cookie-secret=<32-byte-cookie-secret>
secret/talk/local/oauth2-proxy/oidc redirect-url=http://talk.localhost/oauth2/callback
secret/talk/local/oauth2-proxy/oidc cookie-domain=talk.localhost
secret/talk/local/oauth2-proxy/oidc whitelist-domain=.localhost
secret/talk/local/oauth2-proxy/oidc cookie-secure=false
secret/talk/local/oauth2-proxy/oidc insecure-skip-issuer-verification=false
```

Write the local values with:

```sh
export TALK_AUTHZ_DATABASE_URL="postgresql+psycopg://<user>:<password>@<host>:5432/t_authz"
export TALK_ZITADEL_DATABASE_NAME="t_zitadel"
export TALK_ZITADEL_DATABASE_DSN="postgresql://<user>:<password>@talk-host-postgres.talk-local.svc.cluster.local:5432/t_zitadel?sslmode=disable"
export TALK_ZITADEL_MASTERKEY="<32-character-masterkey>"
export TALK_ZITADEL_ADMIN_PASSWORD="<initial-admin-password>"
export TALK_ZITADEL_WEBHOOK_SIGNING_KEY="<zitadel-target-signing-key>"
export TALK_ZITADEL_ISSUER="http://zitadel.localhost"
export TALK_ZITADEL_CLIENT_ID="<zitadel-client-id>"
export TALK_ZITADEL_CLIENT_SECRET="<zitadel-client-secret>"
export TALK_OAUTH2_PROXY_COOKIE_SECRET="<32-byte-cookie-secret>"
export TALK_OAUTH2_PROXY_REDIRECT_URL="http://talk.localhost/oauth2/callback"
export TALK_OAUTH2_PROXY_COOKIE_DOMAIN="talk.localhost"
export TALK_OAUTH2_PROXY_WHITELIST_DOMAIN=".localhost"
export TALK_OAUTH2_PROXY_COOKIE_SECURE="false"
export TALK_OAUTH2_PROXY_INSECURE_SKIP_ISSUER_VERIFICATION="false"

scripts/write-local-vault-secrets.sh
```

By default, `scripts/write-local-vault-secrets.sh` points database URLs at
`talk-host-postgres.talk-local.svc.cluster.local`, which resolves to `host.docker.internal` in the
local cluster. Override `TALK_AUTHZ_DATABASE_URL` and `TALK_ZITADEL_DATABASE_DSN` if your local
Postgres requires a password or different role.

For the first local bring-up, apply platform components first, wait for Zitadel to become ready,
then run `scripts/provision-zitadel-management.py --write-local-vault --sync-local-k8s`.

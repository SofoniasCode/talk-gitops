# Azure Prep

This is the work that can be done locally before an Azure subscription exists. Do not run Azure CLI
commands from this file until the subscription, tenant, resource group, DNS zone, Key Vault, database,
registry, and AKS cluster exist.

## Auth Contract Proven Locally

Local development now uses the same identity shape expected in Azure:

- Zitadel emits `urn:talk:roles` and `urn:talk:organization_id` from `zitadel/actions/talk_roles_claim.js`.
- The Talk management project has role assertion enabled.
- The `oauth2-proxy` OIDC application has access-token, ID-token, and userinfo role assertions enabled.
- `oauth2-proxy` maps `urn:talk:roles` to its `groups` session field and injects `X-Talk-Roles` from `groups`.
- `oauth2-proxy` injects `X-Talk-Organization-Id` from `urn:talk:organization_id`.

The expected `/oauth2/userinfo` shape after login is:

```json
{
  "user": "<zitadel-user-id>",
  "email": "<email-or-user-id>",
  "groups": ["citadel.viewer"],
  "preferredUsername": "<username>",
  "additionalClaims": {
    "urn:talk:organization_id": "<zitadel-org-id>",
    "urn:talk:roles": ["citadel.viewer"]
  }
}
```

## Decisions To Make Before Provisioning Azure

Choose these values before creating cloud resources:

- Environment name: `dev`, `stg`, or `prod`.
- Public app host, for example `talk.dev.example.com`.
- Public Zitadel host, for example `zitadel.dev.example.com`.
- Image registry: keep `ghcr.io/talk/*` or switch overlays to Azure Container Registry image names.
- Database model: one Azure Database for PostgreSQL server with separate databases, or separate servers.
- GitOps controller path: manual `kubectl apply -k` first, then Argo CD, or Argo CD from day one.

The OIDC callback must be:

```text
https://<talk-host>/oauth2/callback
```

The post-logout redirect should start as:

```text
https://<talk-host>/
```

## Non-Secret Values To Prepare Locally

Start from `zitadel/azure-dev.env.example` and replace placeholder domains. Keep it out of shell
history if you add real secrets later.

Important production-like settings:

- `TALK_ZITADEL_OIDC_DEVELOPMENT_MODE=false`
- `TALK_ZITADEL_OAUTH2_PROXY_APP_NAME=oauth2-proxy-dev`
- `TALK_ZITADEL_REDIRECT_URIS=https://<talk-host>/oauth2/callback`
- `TALK_ZITADEL_POST_LOGOUT_URIS=https://<talk-host>/`

The provisioning script is safe to rerun. It creates or updates:

- Talk management project
- Talk roles
- Project role assertion
- OIDC app role/userinfo assertions
- Token action and complement-token triggers

## Secret Matrix

The Azure overlays expect these Azure Key Vault secret names for `dev`. Use the same pattern for
`stg` and `prod`.

```text
talk-dev-authz-database-url
talk-dev-zitadel-masterkey
talk-dev-zitadel-database-dsn
talk-dev-zitadel-database-host
talk-dev-zitadel-database-port
talk-dev-zitadel-database-name
talk-dev-zitadel-database-user
talk-dev-zitadel-admin-password
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

Values that can be generated locally before Azure exists:

```sh
openssl rand -base64 32 # oauth2-proxy cookie secret
openssl rand -hex 16    # Zitadel masterkey candidate, must be exactly 32 characters
openssl rand -base64 32 # initial admin password candidate
openssl rand -base64 32 # identity webhook signing key candidate, unless Zitadel generates it
```

Do not commit generated values.

## Image Registry Prep

Current overlays tag images as:

```text
ghcr.io/talk/authz:<env>
ghcr.io/talk/identity-sync:<env>
ghcr.io/talk/console-api:<env>
ghcr.io/talk/console-web:<env>
ghcr.io/talk/admin-web:<env>
```

If Azure Container Registry is preferred, update the `images` blocks in:

- `services/overlays/azure-dev/kustomization.yaml`
- `services/overlays/azure-stg/kustomization.yaml`
- `services/overlays/azure-prod/kustomization.yaml`
- `apps/overlays/azure-dev/kustomization.yaml`
- `apps/overlays/azure-stg/kustomization.yaml`
- `apps/overlays/azure-prod/kustomization.yaml`

Use `newName` for the ACR repository and keep `newTag` for the environment tag.

## GitOps Placeholders To Replace Later

When Azure exists, replace these placeholder values:

- `platform-components/base/external-secrets/azure-key-vault-clustersecretstore.yaml`
  - `vaultUrl`
- `platform-components/base/external-secrets/azure-workload-identity-serviceaccount.yaml`
  - `azure.workload.identity/client-id`
  - `azure.workload.identity/tenant-id`

The `ClusterSecretStore` is already named `talk-azure-key-vault`, which matches the Azure overlays.

## First Azure Smoke Tests

After deployment and a fresh login:

- `https://<talk-host>/oauth2/userinfo` includes `groups` and `additionalClaims.urn:talk:roles`.
- `https://<talk-host>/console-api/v1/permissions` returns `200`, not `403`.
- `https://<talk-host>/console/` loads JS and CSS assets with JavaScript/CSS MIME types, not `text/html`.
- `authz`, `console-api`, `identity-sync`, `console-web`, `admin-web`, `zitadel`, and `oauth2-proxy` pods are ready.

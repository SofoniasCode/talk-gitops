# talk-platform-gitops

GitOps manifests for JeenTalk platform infrastructure, backend services, and frontend apps.

For local-only preparation before an Azure subscription exists, see `AZURE_PREP.md`.

This repository follows the product architecture notes:

- `platform-components/`: cluster components such as External Secrets, Vault, Zitadel, Redis, observability, and cert-manager.
- `services/base/`: reusable Kustomize bases for backend services.
- `services/overlays/`: environment-specific patches for local, dev, staging, and production.
- `apps/base/`: reusable Kustomize bases for frontend apps.
- `apps/overlays/`: environment-specific app patches.
- `gateway/base/`: Envoy Gateway API resources, oauth2-proxy, and public HTTP routes.
- `gateway/overlays/`: environment-specific gateway namespaces and patches.
- `zitadel/`: Zitadel setup runbooks, token actions, and non-secret examples.
- `argocd-applications/`: ArgoCD app-of-apps entries per environment.

Service-owned migrations run from the same image as the service, either as a release `Job` or an init-container gate where that is acceptable for the environment.

Environment overlays use External Secrets Operator (`external-secrets.io/v1`) to sync runtime
secrets. Azure overlays use Azure Key Vault through `talk-azure-key-vault`; local overlays use
HashiCorp Vault through `talk-hashicorp-vault`.

Required Azure Key Vault secret names:

- `talk-<env>-authz-database-url`
- `talk-<env>-zitadel-masterkey`
- `talk-<env>-zitadel-database-dsn`
- `talk-<env>-zitadel-database-host`
- `talk-<env>-zitadel-database-port`
- `talk-<env>-zitadel-database-name`
- `talk-<env>-zitadel-database-user`
- `talk-<env>-zitadel-admin-password`
- `talk-<env>-identity-sync-zitadel-webhook-signing-key`
- `talk-<env>-zitadel-issuer-url`
- `talk-<env>-zitadel-admin-token`
- `talk-<env>-zitadel-api-host-header`
- `talk-<env>-zitadel-project-id`
- `talk-<env>-oauth2-proxy-client-id`
- `talk-<env>-oauth2-proxy-client-secret`
- `talk-<env>-oauth2-proxy-cookie-secret`
- `talk-<env>-oauth2-proxy-redirect-url`
- `talk-<env>-oauth2-proxy-cookie-domain`
- `talk-<env>-oauth2-proxy-whitelist-domain`
- `talk-<env>-oauth2-proxy-cookie-secure`
- `talk-<env>-oauth2-proxy-insecure-skip-issuer-verification`

Use `dev`, `stg`, or `prod` for `<env>`.

Required local HashiCorp Vault KV v2 paths:

- `secret/talk/local/authz/database` with property `database-url`
- `secret/talk/local/zitadel/config` with properties `masterkey`, `database-dsn`, `database-host`, `database-port`, `database-name`, `database-user`, and `admin-password`
- `secret/talk/local/identity-sync/zitadel-webhook` with property `signing-key`
- `secret/talk/local/console-api/zitadel-admin` with properties `base-url`, `admin-token`, `api-host-header`, and `project-id`
- `secret/talk/local/oauth2-proxy/oidc` with properties `issuer-url`, `client-id`, `client-secret`, `cookie-secret`, `redirect-url`, `cookie-domain`, `whitelist-domain`, and `cookie-secure`

Use `scripts/write-local-vault-secrets.sh` to write baseline local Vault values from environment
variables into your existing localhost Vault. After Zitadel is ready, use
`scripts/provision-zitadel-management.py --write-local-vault --sync-local-k8s` to create the Talk
project, roles, `oauth2-proxy` app, and token-claim action, then sync the real OIDC client values
back into local Vault.

Local Zitadel runs as a platform component and is exposed through the gateway host
`zitadel.localhost`. Use `scripts/bootstrap-local-dev.sh` after installing External Secrets
Operator and Envoy Gateway in the local cluster.

Local app routes are exposed through `talk.localhost`. The bootstrap script patches local CoreDNS
so pods can resolve `zitadel.localhost` to the in-cluster Zitadel service while browsers still use
the public gateway host.

Local overlays do not deploy Postgres or Vault. They use your machine's existing localhost Postgres
through the `talk-host-postgres` service alias and your machine's existing localhost Vault through
`host.docker.internal:8200`. Run `scripts/prepare-local-postgres.sh` to create the expected
`t_authz` and `t_zitadel` databases on that existing Postgres server.

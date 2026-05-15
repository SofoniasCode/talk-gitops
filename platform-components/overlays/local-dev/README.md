# Local Dev Platform Components

This overlay adds local platform dependencies used by Envoy Gateway routes:

- HashiCorp Vault `ClusterSecretStore` for External Secrets Operator, pointing to your host Vault.
- `talk-host-postgres`, an `ExternalName` service that points to your machine's local Postgres
  through `host.docker.internal`.
- Zitadel API/Login in the `talk-local` namespace.

The Vault store follows the official External Secrets Operator HashiCorp Vault provider shape:

- `server`: `http://host.docker.internal:8200`
- `path`: `secret`
- `version`: `v2`
- auth: static token from `external-secrets/talk-vault-token`

This overlay does not deploy Vault. It expects your existing local Vault server to be reachable on
TCP port `8200`. The local token defaults to `root`; patch it or export `VAULT_TOKEN` if your host
Vault uses another token.

Zitadel is reachable through the local gateway host `zitadel.localhost` and uses:

- `ZITADEL_EXTERNALDOMAIN=zitadel.localhost`
- `ZITADEL_EXTERNALPORT=80`
- `ZITADEL_EXTERNALSECURE=false`
- `ZITADEL_DATABASE_POSTGRES_*` from the `zitadel-config` secret

`scripts/bootstrap-local-dev.sh` patches local CoreDNS with a rewrite for `zitadel.localhost` so
in-cluster clients, such as `oauth2-proxy`, can reach Zitadel with the same issuer hostname that
browsers use.

This overlay does not deploy Postgres. It expects your existing local Postgres server to be
reachable on TCP port `5432`. From Kubernetes, that host is addressed as
`talk-host-postgres.talk-local.svc.cluster.local`.

Prepare the two local databases with:

```sh
scripts/prepare-local-postgres.sh
```

By default, Zitadel uses a dedicated `t_zitadel` database. If your local Postgres requires a
different user, password, host, port, or database name, set `TALK_AUTHZ_DATABASE_URL`,
`TALK_ZITADEL_DATABASE_NAME`, and `TALK_ZITADEL_DATABASE_DSN` before seeding Vault.

Seed Vault with:

```sh
export TALK_ZITADEL_WEBHOOK_SIGNING_KEY="local-webhook-signing-key"
export TALK_ZITADEL_CLIENT_ID="<client-id-created-in-local-zitadel>"
export TALK_ZITADEL_CLIENT_SECRET="<client-secret-created-in-local-zitadel>"
export TALK_OAUTH2_PROXY_COOKIE_SECRET="<32-byte-cookie-secret>"
export TALK_OAUTH2_PROXY_REDIRECT_URL="http://talk.localhost/oauth2/callback"

scripts/write-local-vault-secrets.sh
```

Official docs: https://external-secrets.io/latest/provider/hashicorp-vault

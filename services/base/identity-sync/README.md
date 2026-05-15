# identity-sync

`identity-sync` consumes Zitadel webhooks and projects organization and membership state into
the `authz` database. The service does not run migrations; `authz` owns the schema and migration
jobs for these projection tables.

## Zitadel Webhook Target

Create a Zitadel webhook target that sends JSON payloads to:

```text
https://<identity-sync-host>/v1/webhooks/zitadel
```

Use Zitadel's target signing key as the external secret value. The environment overlays sync it
into this Kubernetes Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: identity-sync-zitadel
type: Opaque
stringData:
  webhook-signing-key: <zitadel-target-signing-key>
```

The deployment exposes this value as `ZITADEL_WEBHOOK_SECRET`. When it is set, `identity-sync`
requires the official `ZITADEL-Signature` header to match Zitadel's signed JSON target payload.

## Required Database Secret

`identity-sync` writes into the `authz` database and expects the shared `authz-database` secret,
also created by the environment overlays through External Secrets Operator:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: authz-database
type: Opaque
stringData:
  database-url: postgresql+psycopg://<user>:<password>@<host>:5432/t_authz
```

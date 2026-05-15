# Zitadel

Talk self-hosts Zitadel as a platform component so local development and Azure can use the same
identity boundary.

The base follows the official Zitadel self-hosting guidance:

- PostgreSQL via `ZITADEL_DATABASE_POSTGRES_*`
- a fixed 32-character masterkey
- explicit external domain, port, and secure settings
- `init schema` followed by `start-from-setup` for pre-created databases
- Login v2 as a companion container sharing the generated login client token

The base expects a Kubernetes Secret named `zitadel-config` with:

- `masterkey`
- `database-dsn`
- `database-host`
- `database-port`
- `database-name`
- `database-user`
- `admin-password`

Official docs:

- https://zitadel.com/docs/self-hosting/deploy/kubernetes/configuration
- https://zitadel.com/docs/self-hosting/deploy/kubernetes/database

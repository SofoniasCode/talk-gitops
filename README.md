# talk-gitops

GitOps deployment manifests for the Talk platform. This repository is watched by
Argo CD for continuous deployment.

## Repository Layout

```
chart/
├── talk/                  # Helm chart (templates, _helpers.tpl, defaults)
├── values-dev.yaml        # Azure dev values (image tags updated by CI)
├── values-stg.yaml        # Azure staging values
└── values-prod.yaml       # Azure production values
argocd-applications/       # Argo CD Application manifests per environment
scripts/
└── bootstrap-local-dev.sh # Local dev deploy (Kind + Vault + local Postgres)
```

## Related Repositories

| Repo | Purpose |
|------|---------|
| `talk` | Application code (Python services + web apps), CI workflows |
| `talk-gitops` | Helm chart, Argo CD applications, per-environment values (this repo) |
| `talk-infra` | Terraform, bootstrap scripts, secret provisioning |

## How Deployment Works

1. A push to `talk` triggers CI which builds images, pushes to ACR, and updates
   the image tag in `chart/values-<env>.yaml` via a commit to this repo
2. Argo CD detects the values change and syncs the Helm chart to the cluster

## Usage

**Direct Helm install:**

```sh
helm install talk chart/talk -n talk-dev --create-namespace -f chart/values-dev.yaml
```

**Argo CD (recommended for production):**

```sh
kubectl apply -f argocd-applications/dev/talk.yaml
```

**Upgrade after values change:**

```sh
helm upgrade talk chart/talk -n talk-dev -f chart/values-dev.yaml
```

## Required Azure Key Vault Secrets

The Helm chart uses External Secrets Operator to pull secrets from Azure Key Vault.
All keys follow the pattern `talk-<env>-<component>-<key>`:

- `talk-<env>-authz-database-url`
- `talk-<env>-zitadel-masterkey`
- `talk-<env>-zitadel-database-{dsn,host,port,name,user,password}`
- `talk-<env>-zitadel-{issuer-url,admin-token,admin-password,api-host-header,project-id}`
- `talk-<env>-identity-sync-zitadel-webhook-signing-key`
- `talk-<env>-oauth2-proxy-{client-id,client-secret,cookie-secret,redirect-url,cookie-domain,whitelist-domain,cookie-secure,insecure-skip-issuer-verification}`

See `talk-infra` for scripts that populate these secrets.

## Legacy Kustomize (to be removed)

The `platform-components/`, `gateway/`, `apps/`, and `services/` directories contain
the old Kustomize base+overlay manifests. These are superseded by `chart/talk/` and
will be removed after the Helm migration is verified.

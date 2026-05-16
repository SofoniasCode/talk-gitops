# talk-gitops

GitOps deployment manifests for the Talk platform. Argo CD watches this
repository and reconciles the Helm chart in `chart/talk/` against the
cluster.

## Repository layout

```
chart/
├── talk/                  # Helm workload chart (templates, _helpers.tpl, defaults)
├── values-dev.yaml        # Per-env values, image tags rewritten by CI
└── REGENERATE.md          # How to regenerate values-<env>.yaml from Terraform
argocd-bootstrap/          # Tiny Helm chart that emits the per-env Argo Application
scripts/
└── bootstrap-local-dev.sh # Local dev (Kind + Vault + local Postgres)
```

## Related repositories

| Repo            | Purpose                                                       |
| --------------- | ------------------------------------------------------------- |
| `talk`          | Application code (Python services + web apps), CI workflows   |
| `talk-gitops`   | Helm chart, Argo CD bootstrap, per-environment values         |
| `talk-infra`    | Terraform, bootstrap scripts, Key Vault secret provisioning   |

## How deployment works

1. A push to `talk` triggers CI, which builds images, pushes to ACR, and
   commits new image tags into `chart/values-<env>.yaml` here.
2. Argo CD detects the values change and syncs `chart/talk/` to the cluster.

## Usage

### First-time install (per environment)

```sh
helm template talk-bootstrap ./argocd-bootstrap \
  -f ./argocd-bootstrap/values-<env>.yaml \
  | kubectl apply -f -
```

That registers a single Argo CD `Application` (`talk-<env>`) that owns the
rest of the deployment.

### Direct Helm install (no Argo CD)

```sh
helm install talk chart/talk -n talk-<env> --create-namespace \
  -f chart/values-<env>.yaml
```

### Regenerating `chart/values-<env>.yaml`

See [chart/REGENERATE.md](chart/REGENERATE.md) — values files are generated
from `terraform output -raw helm_values_yaml` in `talk-infra`.

## Required Azure Key Vault secrets

The Helm chart uses External Secrets Operator to pull secrets from Azure
Key Vault. Keys follow `talk-<env>-<component>-<key>`:

- `talk-<env>-authz-database-url`
- `talk-<env>-zitadel-masterkey`
- `talk-<env>-zitadel-database-{dsn,host,port,name,user,password}`
- `talk-<env>-zitadel-{issuer-url,admin-token,admin-password,api-host-header,project-id}`
- `talk-<env>-identity-sync-zitadel-webhook-signing-key`
- `talk-<env>-oauth2-proxy-{public,console}-{client-id,client-secret,cookie-secret,cookie-domain,whitelist-domain,cookie-secure,insecure-skip-issuer-verification}`

See `talk-infra/scripts/populate-keyvault-secrets.sh` for the provisioning
script.

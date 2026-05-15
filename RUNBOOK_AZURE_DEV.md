# Azure Environment Runbook

End-to-end steps to provision a Talk environment on Azure from scratch. Each environment
(`dev`, `stg`, `prod`) gets its own AKS cluster, PostgreSQL server, Key Vault, and Argo CD
installation. This runbook is designed to be repeatable -- follow it once per environment,
per tenant.

**Architecture: one cluster per environment.**

| Tenant | Rollout Order | Domain |
|--------|---------------|--------|
| Personal | dev only | telodev.com |
| Company | stg, then dev, then prod | `<company-domain>` |

## Prerequisites

Install these tools locally:

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
- [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.5)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) (v3)
- [GitHub CLI](https://cli.github.com/) (`gh`)
- [Argo CD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) (`argocd`)

## Values To Decide Per Tenant / Environment

| Value | Personal dev | Company stg | Company dev | Company prod |
|-------|-------------|-------------|-------------|-------------|
| Azure subscription | personal | company | company | company |
| Environment | `dev` | `stg` | `dev` | `prod` |
| Domain | `telodev.com` | `<company>` | `<company>` | `<company>` |
| GitHub org / repo | `SofoniasCode/talk` | `CompanyOrg/talk` | `CompanyOrg/talk` | `CompanyOrg/talk` |
| GitHub gitops repo | `SofoniasCode/talk-gitops` | `CompanyOrg/talk-gitops` | `CompanyOrg/talk-gitops` | `CompanyOrg/talk-gitops` |

Environment-specific files are isolated in Kustomize overlays (`overlays/azure-<env>/`).
Base manifests in `base/` are shared across all environments and should not contain
environment-specific values.

---

## Phase 1: Azure Login and Terraform

```sh
az login
az account set --subscription "<subscription-id>"

cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: subscription_id, postgres_admin_password, domain, github_repo, location
```

> **IMPORTANT:** `github_repo` must use the exact GitHub casing (e.g. `SofoniasCode/talk`,
> not `sofoniascode/talk`). Azure federated credentials are case-sensitive.

```sh
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Save outputs for later steps
terraform output -json > /tmp/talk-tf-outputs.json
```

Key outputs you'll need:

| Output | Used For |
|--------|----------|
| `dns_zone_nameservers` | NS records in your domain registrar |
| `key_vault_name` | Key Vault secret scripts |
| `key_vault_url` | ESO ClusterSecretStore |
| `postgres_fqdn` | Database connection strings |
| `acr_login_server` | Kustomize image overlays |
| `eso_managed_identity_client_id` | Workload identity |
| `github_actions_client_id` | CI/CD setup |

## Phase 2: DNS Delegation

Add NS records in your domain registrar (e.g. GoDaddy) for the `<env>` subdomain:

1. Go to DNS management for your domain
2. Add NS records for `dev` (or `stg`/`prod`) pointing to the `dns_zone_nameservers` output
3. Wait for propagation

```sh
dig NS dev.yourdomain.com
```

## Phase 3: Connect to AKS and Bootstrap

```sh
export TALK_AKS_CLUSTER="$(terraform output -raw aks_cluster_name)"
export TALK_RESOURCE_GROUP="$(terraform output -raw resource_group_name)"

az aks get-credentials \
  --resource-group "$TALK_RESOURCE_GROUP" \
  --name "$TALK_AKS_CLUSTER"

kubectl get nodes  # verify connectivity

./scripts/bootstrap-aks.sh
```

This installs: External Secrets Operator, cert-manager, Envoy Gateway, Argo CD.
Save the Argo CD admin password printed at the end.

## Phase 4: Update Kustomize Overlays

Using the Terraform outputs, update the overlay files for your environment.
If deploying `dev`, edit the files in `overlays/azure-dev/`. For a new company
environment, you may copy `azure-dev` to a new overlay (e.g. `azure-company-dev`).

Files to update with Terraform outputs:

1. **`platform-components/overlays/azure-<env>/eso-patches.yaml`** -- vault URL, managed identity
2. **`platform-components/overlays/azure-<env>/zitadel-patches.yaml`** -- domain names
3. **`gateway/overlays/azure-<env>/`** -- domain names in HTTPRoutes and Gateway
4. **`apps/overlays/azure-<env>/kustomization.yaml`** -- ACR `newName`
5. **`services/overlays/azure-<env>/kustomization.yaml`** -- ACR `newName`

## Phase 5: Populate Key Vault Secrets

```sh
export TALK_KEY_VAULT_NAME="$(terraform output -raw key_vault_name)"
export TALK_POSTGRES_FQDN="$(terraform output -raw postgres_fqdn)"
export TALK_POSTGRES_ADMIN_USER="talkadmin"
export TALK_POSTGRES_ADMIN_PASSWORD="<your postgres password from tfvars>"
export TALK_PUBLIC_HOST="talk.dev.yourdomain.com"
export TALK_ZITADEL_HOST="zitadel.dev.yourdomain.com"
export TALK_ENV="dev"

./scripts/populate-keyvault-secrets.sh
```

Save the generated secrets printed at the end.

## Phase 6: Deploy Platform Components and Gateway

```sh
# Apply platform components (Zitadel, External Secrets store)
kubectl apply -k platform-components/overlays/azure-dev

# Wait for Zitadel to start
kubectl -n talk-dev wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=zitadel --timeout=300s
```

## Phase 7: Set Up CI/CD

This configures Argo CD repo credentials, GitHub Actions secrets, and registers
Argo CD Applications -- all in one script.

```sh
export TALK_ENV="dev"
export TALK_GITHUB_APP_REPO="YourOrg/talk"
export TALK_GITHUB_GITOPS_REPO="YourOrg/talk-gitops"
export TALK_GITOPS_PAT="ghp_..."  # GitHub PAT with repo scope for gitops repo
export TALK_ACR_NAME="$(terraform output -raw acr_name)"
export TALK_AZURE_CLIENT_ID="$(terraform output -raw github_actions_client_id)"
export TALK_AZURE_TENANT_ID="$(terraform output -raw github_actions_tenant_id)"
export TALK_AZURE_SUBSCRIPTION_ID="<subscription-id>"

./scripts/setup-cicd.sh
```

## Phase 8: Build and Push Initial Images

Trigger the first build to populate ACR:

```sh
cd ../talk
gh workflow run "Build and Push" --ref dev -f force_all=true
gh run watch  # wait for completion
cd ../talk-gitops
```

Or build locally:

```sh
ACR_NAME="talkdevacr"
az acr login --name "$ACR_NAME"
cd ../talk

for svc in authz identity-sync console-api; do
  docker build -f deployments/docker/Dockerfile.python-service \
    --build-arg PACKAGE="talk-${svc}" --build-arg SERVICE="$svc" \
    -t "${ACR_NAME}.azurecr.io/talk/${svc}:dev" .
  docker push "${ACR_NAME}.azurecr.io/talk/${svc}:dev"
done

for app in console admin; do
  docker build -f deployments/docker/Dockerfile.web-app \
    --build-arg APP="$app" \
    -t "${ACR_NAME}.azurecr.io/talk/${app}-web:dev" .
  docker push "${ACR_NAME}.azurecr.io/talk/${app}-web:dev"
done

cd ../talk-gitops
```

## Phase 9: Provision Zitadel (OIDC App, Roles, Secrets)

Once Zitadel is running, provision the Talk project, OIDC application, and write
the real secrets back to Key Vault -- all in one command:

```sh
# Get the admin PAT
ADMIN_PAT=$(kubectl -n talk-dev exec deploy/zitadel -c login -- \
  cat /zitadel/bootstrap/admin-service.pat)

export TALK_ZITADEL_ADMIN_PAT="$ADMIN_PAT"
export TALK_ZITADEL_API_URL="https://zitadel.dev.yourdomain.com"
export TALK_ZITADEL_ISSUER="https://zitadel.dev.yourdomain.com"
export TALK_ZITADEL_REDIRECT_URIS="https://talk.dev.yourdomain.com/oauth2/callback"
export TALK_ZITADEL_POST_LOGOUT_URIS="https://talk.dev.yourdomain.com/"
export TALK_ZITADEL_OAUTH2_PROXY_APP_NAME="oauth2-proxy-dev"
export TALK_ZITADEL_OIDC_DEVELOPMENT_MODE="false"
export TALK_ZITADEL_REGENERATE_CLIENT_SECRET="true"
export TALK_KEY_VAULT_NAME="$(terraform output -raw key_vault_name)"
export TALK_ENV="dev"
export TALK_K8S_NAMESPACE="talk-dev"

python3 scripts/provision-zitadel-management.py \
  --write-azure-keyvault \
  --sync-azure-k8s \
  --grant-admin your-email@example.com
```

This single command:
1. Creates/finds the Talk Management project and roles in Zitadel
2. Creates the OIDC application for oauth2-proxy
3. Writes client ID, client secret, project ID, and admin token to Azure Key Vault
4. Refreshes ExternalSecrets and restarts oauth2-proxy + console-api
5. Grants `citadel.admin` + `organization.owner` roles to the specified user

## Phase 10: Configure Microsoft Login (Optional)

If you want Microsoft/Azure AD login:

```sh
export ZITADEL_DOMAIN="zitadel.dev.yourdomain.com"
export ZITADEL_PAT="$ADMIN_PAT"
export MICROSOFT_CLIENT_ID="$(terraform output -raw microsoft_idp_client_id)"
export MICROSOFT_CLIENT_SECRET="$(az keyvault secret show \
  --vault-name "$TALK_KEY_VAULT_NAME" \
  --name talk-dev-microsoft-idp-client-secret \
  --query value -o tsv)"

./scripts/configure-zitadel-microsoft-idp.sh
```

## Phase 11: Smoke Tests

```sh
# Zitadel login page loads
curl -sI https://zitadel.dev.yourdomain.com/ui/v2/login/ | head -3

# App redirects to Zitadel for login
curl -sI https://talk.dev.yourdomain.com/ | head -3

# Argo CD apps are healthy
kubectl -n argocd get applications
```

## Replicating For Another Tenant

1. Fork/copy the `talk` and `talk-gitops` repos to the new GitHub org
2. Copy `terraform.tfvars.example` -> `terraform.tfvars`, fill in company values
3. Create new Kustomize overlays if the company needs different naming
4. Follow this runbook from Phase 1
5. The only manual steps are: DNS delegation and creating the `GITOPS_PAT`

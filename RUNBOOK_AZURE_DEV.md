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
- [Docker](https://docs.docker.com/get-docker/) (for local image builds)

## Values To Decide Per Tenant / Environment

| Value | Personal dev | Company stg | Company dev | Company prod |
|-------|-------------|-------------|-------------|-------------|
| Azure subscription | personal | company | company | company |
| Environment | `dev` | `stg` | `dev` | `prod` |
| Domain | `telodev.com` | `<company>` | `<company>` | `<company>` |
| GitHub org / repo | personal | company | company | company |
| ACR name | `talkdevacr` | `talkstgacr` | `talkdevacr` | `talkprodacr` |
| Namespace | `talk-dev` | `talk-stg` | `talk-dev` | `talk-prod` |
| Cluster | `talk-dev-aks` | `talk-stg-aks` | `talk-dev-aks` | `talk-prod-aks` |
| Key Vault | `talk-dev-kv` | `talk-stg-kv` | `talk-dev-kv` | `talk-prod-kv` |

Files that reference per-environment values (substitute `<env>` = `dev`, `stg`, or `prod`):

- `infra/terraform/terraform.tfvars` (or `terraform.<env>.tfvars`)
- `services/overlays/azure-<env>/kustomization.yaml` (ACR `newName`)
- `apps/overlays/azure-<env>/kustomization.yaml` (ACR `newName`)
- `argocd-applications/<env>/*.yaml` (repo URL)
- `platform-components/overlays/azure-<env>/zitadel-patches.yaml` (domain)
- `platform-components/overlays/azure-<env>/eso-patches.yaml` (vault URL, identity)
- `.github/workflows/build-and-push.yml` (ACR name)

The base external-secrets files (`platform-components/base/external-secrets/`) contain
placeholder values. Each overlay patches them via `eso-patches.yaml` with cluster-specific
values from Terraform outputs.

---

## Phase 1: Terraform State Backend

Before running Terraform, create a storage account for remote state. This only needs to happen
once per Azure subscription.

```sh
az login
az account set --subscription "<subscription-id>"

az group create --name talk-tfstate-rg --location westeurope
az storage account create \
  --name talktfstate \
  --resource-group talk-tfstate-rg \
  --location westeurope \
  --sku Standard_LRS
az storage container create \
  --name tfstate \
  --account-name talktfstate
```

## Phase 2: Provision Azure Infrastructure

Each environment gets its own Terraform state file and tfvars.

```sh
cd infra/terraform

# For dev (personal):
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your subscription_id, postgres password, etc.

terraform init -backend-config="key=dev.terraform.tfstate"
terraform plan -out=tfplan
terraform apply tfplan

# For stg (company, later):
# cp terraform.tfvars.stg.example terraform.stg.tfvars
# terraform init -backend-config="key=stg.terraform.tfstate" -reconfigure
# terraform plan -var-file=terraform.stg.tfvars -out=tfplan
# terraform apply tfplan
```

Save the outputs -- you will need them for the next steps:

```sh
terraform output -json > /tmp/talk-tf-outputs.json
```

Key outputs:

| Output | Used For |
|--------|----------|
| `dns_zone_nameservers` | NS records to add in GoDaddy |
| `key_vault_name` | Secrets population script |
| `key_vault_url` | ClusterSecretStore manifest |
| `postgres_fqdn` | Secrets population script |
| `acr_login_server` | Kustomize image overlays |
| `eso_managed_identity_client_id` | Workload identity SA annotation |
| `eso_managed_identity_tenant_id` | Workload identity SA annotation |
| `aks_cluster_name` | kubectl / bootstrap script |
| `resource_group_name` | az aks get-credentials |

## Phase 3: DNS Delegation

Add NS records in GoDaddy for the `dev` subdomain of your domain (e.g., `telodev.com`):

1. Log into GoDaddy DNS management for `telodev.com`
2. Add an NS record set for `dev` pointing to each nameserver from the `dns_zone_nameservers` output
3. Wait for propagation (can take minutes to hours)

Verify:

```sh
dig NS dev.telodev.com
```

## Phase 4: Update GitOps Manifests With Real Values

Using the Terraform outputs, update the placeholder values in the gitops repo.

### ESO Patches (vault URL and workload identity)

Edit `platform-components/overlays/azure-<env>/eso-patches.yaml` with the Terraform outputs.
Do NOT edit the base files -- each overlay patches them independently so different clusters
can point at different Key Vaults.

```yaml
# In eso-patches.yaml, replace:
#   vaultUrl with key_vault_url
#   client-id with eso_managed_identity_client_id
#   tenant-id with eso_managed_identity_tenant_id
```

### ACR Image Names (if ACR login server differs from default)

Check `terraform output acr_login_server`. If it differs from `talkdevacr.azurecr.io`, update:

- `services/overlays/azure-dev/kustomization.yaml`
- `apps/overlays/azure-dev/kustomization.yaml`

### Argo CD Repo URL

Update `argocd-applications/dev/*.yaml` with your actual GitHub repo URL.

## Phase 5: Connect to AKS and Bootstrap

```sh
export TALK_AKS_CLUSTER="talk-dev-aks"
export TALK_RESOURCE_GROUP="talk-dev-rg"

az aks get-credentials \
  --resource-group "$TALK_RESOURCE_GROUP" \
  --name "$TALK_AKS_CLUSTER"

kubectl get nodes  # verify connectivity

./scripts/bootstrap-aks.sh
```

This installs:
1. External Secrets Operator
2. cert-manager
3. Envoy Gateway
4. Argo CD

Save the Argo CD admin password printed at the end.

## Phase 6: Populate Key Vault Secrets

```sh
export TALK_KEY_VAULT_NAME="talk-dev-kv"
export TALK_POSTGRES_FQDN="<postgres_fqdn from terraform output>"
export TALK_POSTGRES_ADMIN_USER="talkadmin"
export TALK_POSTGRES_ADMIN_PASSWORD="<your postgres password>"

./scripts/populate-keyvault-secrets.sh
```

Save the generated secrets printed at the end (masterkey, admin password, cookie secret,
webhook signing key). These are not retrievable from Key Vault later without explicit read access.

## Phase 7: Deploy Platform Components

Apply the platform components (External Secrets store, Zitadel, etc.):

```sh
kubectl apply -k platform-components/overlays/azure-dev
```

Wait for Zitadel to become ready:

```sh
kubectl -n talk-dev wait --for=condition=Ready pod -l app.kubernetes.io/name=zitadel --timeout=300s
```

## Phase 8: Build and Push Initial Images

Before Argo CD can deploy services and apps, images must exist in ACR.

```sh
ACR_NAME="talkdevacr"
az acr login --name "$ACR_NAME"

# From the talk repo root:
cd ../talk

# Build and push services
for svc in authz identity-sync console-api; do
  PACKAGE="talk-${svc}"
  docker build \
    -f deployments/docker/Dockerfile.python-service \
    --build-arg PACKAGE="$PACKAGE" \
    --build-arg SERVICE="$svc" \
    -t "${ACR_NAME}.azurecr.io/talk/${svc}:dev" .
  docker push "${ACR_NAME}.azurecr.io/talk/${svc}:dev"
done

# Build and push apps
for app in console admin; do
  docker build \
    -f deployments/docker/Dockerfile.web-app \
    --build-arg APP="$app" \
    -t "${ACR_NAME}.azurecr.io/talk/${app}-web:dev" .
  docker push "${ACR_NAME}.azurecr.io/talk/${app}-web:dev"
done

cd ../talk-gitops
```

## Phase 9: Register Argo CD Applications

```sh
kubectl apply -f argocd-applications/dev/
```

This registers four Argo CD Applications:
- `talk-platform-dev` -- platform components (Zitadel, External Secrets, etc.)
- `talk-services-dev` -- backend services (authz, identity-sync, console-api)
- `talk-apps-dev` -- frontend apps (console, admin)
- `talk-gateway-dev` -- Envoy Gateway routes, oauth2-proxy

Monitor sync status:

```sh
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
# Open https://localhost:8080, login with admin / <password from bootstrap>
```

Or via CLI:

```sh
kubectl -n argocd get applications
```

## Phase 10: Provision Zitadel

Once Zitadel is running and accessible, provision the Talk project, roles, and OIDC app.

First, get the Zitadel admin PAT (if using the bootstrap PAT from the init container):

```sh
kubectl -n talk-dev exec deploy/zitadel -c api -- cat /zitadel/bootstrap/admin-service.pat
```

Then run the provisioning script:

```sh
export TALK_ZITADEL_ISSUER="https://zitadel.dev.telodev.com"
export TALK_ZITADEL_API_URL="https://zitadel.dev.telodev.com"
export TALK_ZITADEL_ADMIN_PAT="<pat-from-above>"
export TALK_ZITADEL_ORGANIZATION_NAME="ZITADEL"
export TALK_ZITADEL_PROJECT_NAME="Talk Management"
export TALK_ZITADEL_OAUTH2_PROXY_APP_NAME="oauth2-proxy-dev"
export TALK_ZITADEL_OIDC_DEVELOPMENT_MODE="false"
export TALK_ZITADEL_REDIRECT_URIS="https://talk.dev.telodev.com/oauth2/callback"
export TALK_ZITADEL_POST_LOGOUT_URIS="https://talk.dev.telodev.com/"

./scripts/provision-zitadel-management.py
```

The script outputs:
- OIDC client ID
- OIDC client secret
- Project ID

Write these back to Key Vault:

```sh
az keyvault secret set --vault-name "$TALK_KEY_VAULT_NAME" --name talk-dev-oauth2-proxy-client-id --value "<client-id>"
az keyvault secret set --vault-name "$TALK_KEY_VAULT_NAME" --name talk-dev-oauth2-proxy-client-secret --value "<client-secret>"
az keyvault secret set --vault-name "$TALK_KEY_VAULT_NAME" --name talk-dev-zitadel-project-id --value "<project-id>"
az keyvault secret set --vault-name "$TALK_KEY_VAULT_NAME" --name talk-dev-zitadel-admin-token --value "<pat>"
```

Restart oauth2-proxy to pick up the new secrets:

```sh
kubectl -n talk-dev rollout restart deploy/oauth2-proxy
```

## Phase 11: DNS A Records

After Envoy Gateway provisions a LoadBalancer, get the external IP:

```sh
kubectl -n talk-dev get svc -l gateway.networking.k8s.io/owning-gateway-name=talk-public-gateway
```

Add A records in Azure DNS:

```sh
EXTERNAL_IP="<load-balancer-ip>"
az network dns record-set a add-record \
  --resource-group talk-dev-rg \
  --zone-name dev.telodev.com \
  --record-set-name talk \
  --ipv4-address "$EXTERNAL_IP"
az network dns record-set a add-record \
  --resource-group talk-dev-rg \
  --zone-name dev.telodev.com \
  --record-set-name zitadel \
  --ipv4-address "$EXTERNAL_IP"
```

## Phase 12: TLS (cert-manager)

Create a ClusterIssuer for Let's Encrypt and annotate the Gateway for automatic certificate
provisioning. This is environment-specific and should be added to the gateway overlay.

## Phase 13: Smoke Tests

```sh
# Zitadel login page loads
curl -sI https://zitadel.dev.telodev.com/ui/v2/login/ | head -5

# oauth2-proxy redirects to Zitadel
curl -sI https://talk.dev.telodev.com/ | head -5

# After logging in, check userinfo
curl -s https://talk.dev.telodev.com/oauth2/userinfo -H "Cookie: <session-cookie>" | jq .

# Console API returns 200
curl -s https://talk.dev.telodev.com/console-api/v1/permissions -H "Cookie: <session-cookie>"
```

## Phase 14: CI/CD Setup (GitHub Actions)

The `build-and-push.yml` workflow authenticates to ACR via Azure federated identity (OIDC).
Set up a service principal or managed identity for GitHub Actions:

```sh
# Create an app registration for GitHub Actions
az ad app create --display-name "talk-github-actions"
APP_ID=$(az ad app list --display-name "talk-github-actions" --query '[0].appId' -o tsv)
az ad sp create --id "$APP_ID"
SP_OID=$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv)

# Grant AcrPush on the container registry
ACR_ID=$(az acr show --name talkdevacr --query id -o tsv)
az role assignment create --assignee "$SP_OID" --role AcrPush --scope "$ACR_ID"

# Federate with GitHub Actions OIDC
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<github-org>/<repo>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

Then set these GitHub Actions secrets in the `talk` repo:
- `AZURE_CLIENT_ID` = the app registration's `appId`
- `AZURE_TENANT_ID` = your Azure tenant ID
- `AZURE_SUBSCRIPTION_ID` = your subscription ID

## Local Development Against Azure Dev

For day-to-day coding, you develop locally and point auth at the cloud Zitadel:

```sh
# In your local .env or shell
export ZITADEL_ISSUER_URL="https://zitadel.dev.telodev.com"
export ZITADEL_PROJECT_ID="<project-id-from-provision-step>"
```

Your local services validate JWTs against the cloud Zitadel JWKS endpoint. No local
Kind cluster or Vault is needed just for development. The cloud Postgres holds all state.

## Replicating For Another Tenant or Environment

1. Copy the appropriate `terraform.tfvars.<env>.example` and fill in the new subscription, domain, etc.
2. Run `terraform init -backend-config="key=<env>.terraform.tfstate" -reconfigure` to switch state.
3. Run `terraform plan -var-file=terraform.<env>.tfvars` and apply.
4. Update the overlay files listed in the table at the top for the target `<env>`.
5. Follow this runbook from Phase 3 onward for the new cluster.

For production, note that the Argo CD Applications have `prune: false` to prevent accidental
deletion of resources when manifests are removed from git. Review sync diffs manually.

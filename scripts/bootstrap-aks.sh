#!/usr/bin/env bash
set -euo pipefail

# Bootstraps a fresh AKS cluster with the operators and controllers
# needed before any application manifests can be applied.
#
# Prerequisites:
#   - az cli logged in, subscription selected
#   - kubectl configured to target the AKS cluster
#   - helm v3 installed
#   - Terraform outputs available (or pass values via environment)
#
# Usage:
#   export TALK_AKS_CLUSTER="talk-dev-aks"
#   export TALK_RESOURCE_GROUP="talk-dev-rg"
#   az aks get-credentials --resource-group "$TALK_RESOURCE_GROUP" --name "$TALK_AKS_CLUSTER"
#   ./scripts/bootstrap-aks.sh

TALK_AKS_CLUSTER="${TALK_AKS_CLUSTER:?Set TALK_AKS_CLUSTER}"
TALK_RESOURCE_GROUP="${TALK_RESOURCE_GROUP:?Set TALK_RESOURCE_GROUP}"
TALK_NAMESPACE="${TALK_NAMESPACE:-talk-${TALK_ENV:-dev}}"

echo "==> Bootstrapping AKS cluster: $TALK_AKS_CLUSTER"

# ── 1. External Secrets Operator ──────────────────────────────────────
echo "==> Installing External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io || true
helm repo update external-secrets
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --wait

# ── 2. cert-manager ──────────────────────────────────────────────────
echo "==> Installing cert-manager"
helm repo add jetstack https://charts.jetstack.io || true
helm repo update jetstack
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait

# ── 3. Envoy Gateway ─────────────────────────────────────────────────
echo "==> Installing Envoy Gateway"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.7.3 \
  --namespace envoy-gateway-system \
  --create-namespace \
  --wait
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available

# ── 4. Argo CD ───────────────────────────────────────────────────────
echo "==> Installing Argo CD"
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo update argo
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set 'configs.params.server\.insecure=true' \
  --set server.service.type=ClusterIP \
  --wait

echo ""
echo "==> Retrieving initial Argo CD admin password"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
echo "    Argo CD admin password: $ARGOCD_PASSWORD"
echo "    Access via: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""

# ── 5. Create application namespace ──────────────────────────────────
echo "==> Creating ${TALK_NAMESPACE} namespace"
kubectl create namespace "$TALK_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> Bootstrap complete."
echo ""
echo "Next steps:"
echo "  1. Run scripts/populate-keyvault-secrets.sh to write secrets to Azure Key Vault"
echo "  2. Update platform-components/base/external-secrets/ with real identity values"
echo "  3. Apply platform-components: kubectl apply -k platform-components/overlays/azure-dev"
echo "  4. Register Argo CD Applications: kubectl apply -f argocd-applications/dev/"

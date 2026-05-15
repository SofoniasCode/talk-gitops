#!/usr/bin/env bash
set -euo pipefail

# Sets up the CI/CD integration between GitHub Actions, ACR, and Argo CD.
# Run this after Terraform and bootstrap-aks.sh, before triggering builds.
#
# What it does:
#   1. Configures Argo CD with credentials to pull from a private gitops repo
#   2. Sets GitHub Actions secrets for Azure OIDC authentication
#   3. Sets GitHub Actions variables (ACR_NAME, GITOPS_REPO)
#   4. Registers Argo CD Applications for the target environment
#
# Prerequisites:
#   - kubectl configured to target the AKS cluster
#   - gh CLI authenticated to the correct GitHub account
#   - Terraform outputs available
#   - A GitHub PAT with repo scope for the gitops repo (TALK_GITOPS_PAT)
#
# Usage:
#   export TALK_ENV="dev"
#   export TALK_GITHUB_APP_REPO="MyOrg/talk"
#   export TALK_GITHUB_GITOPS_REPO="MyOrg/talk-gitops"
#   export TALK_GITOPS_PAT="ghp_..."
#   export TALK_ACR_NAME="talkdevacr"
#   export TALK_AZURE_CLIENT_ID="<from terraform output github_actions_client_id>"
#   export TALK_AZURE_TENANT_ID="<from terraform output>"
#   export TALK_AZURE_SUBSCRIPTION_ID="<subscription id>"
#   ./scripts/setup-cicd.sh

TALK_ENV="${TALK_ENV:?Set TALK_ENV (dev, stg, prod)}"
TALK_GITHUB_APP_REPO="${TALK_GITHUB_APP_REPO:?Set TALK_GITHUB_APP_REPO (e.g. MyOrg/talk)}"
TALK_GITHUB_GITOPS_REPO="${TALK_GITHUB_GITOPS_REPO:?Set TALK_GITHUB_GITOPS_REPO (e.g. MyOrg/talk-gitops)}"
TALK_GITOPS_PAT="${TALK_GITOPS_PAT:?Set TALK_GITOPS_PAT (GitHub PAT with repo scope)}"
TALK_ACR_NAME="${TALK_ACR_NAME:?Set TALK_ACR_NAME}"
TALK_AZURE_CLIENT_ID="${TALK_AZURE_CLIENT_ID:?Set TALK_AZURE_CLIENT_ID}"
TALK_AZURE_TENANT_ID="${TALK_AZURE_TENANT_ID:?Set TALK_AZURE_TENANT_ID}"
TALK_AZURE_SUBSCRIPTION_ID="${TALK_AZURE_SUBSCRIPTION_ID:?Set TALK_AZURE_SUBSCRIPTION_ID}"

GITOPS_REPO_URL="https://github.com/${TALK_GITHUB_GITOPS_REPO}.git"

echo "==> Setting up CI/CD for environment: ${TALK_ENV}"
echo "    App repo:    ${TALK_GITHUB_APP_REPO}"
echo "    GitOps repo: ${TALK_GITHUB_GITOPS_REPO}"
echo "    ACR:         ${TALK_ACR_NAME}"

# ── 1. Argo CD repo credentials ─────────────────────────────────────
echo ""
echo "==> Configuring Argo CD repo credentials"

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)

if [ -n "$ARGOCD_PASSWORD" ]; then
  kubectl port-forward svc/argocd-server -n argocd 8443:443 &>/dev/null &
  PF_PID=$!
  sleep 3

  argocd login localhost:8443 \
    --username admin \
    --password "$ARGOCD_PASSWORD" \
    --insecure \
    --grpc-web 2>/dev/null

  argocd repo add "$GITOPS_REPO_URL" \
    --username "git" \
    --password "$TALK_GITOPS_PAT" \
    --upsert 2>/dev/null

  echo "    Added ${GITOPS_REPO_URL} to Argo CD"

  kill "$PF_PID" 2>/dev/null || true
  wait "$PF_PID" 2>/dev/null || true
else
  echo "    WARNING: Could not get Argo CD admin password. Add repo credentials manually."
fi

# ── 2. GitHub Actions secrets ────────────────────────────────────────
echo ""
echo "==> Setting GitHub Actions secrets on ${TALK_GITHUB_APP_REPO}"

gh secret set AZURE_CLIENT_ID       --repo "$TALK_GITHUB_APP_REPO" --body "$TALK_AZURE_CLIENT_ID"
gh secret set AZURE_TENANT_ID       --repo "$TALK_GITHUB_APP_REPO" --body "$TALK_AZURE_TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --repo "$TALK_GITHUB_APP_REPO" --body "$TALK_AZURE_SUBSCRIPTION_ID"
gh secret set GITOPS_PAT            --repo "$TALK_GITHUB_APP_REPO" --body "$TALK_GITOPS_PAT"

echo "    Set AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, GITOPS_PAT"

# ── 3. GitHub Actions variables ──────────────────────────────────────
echo ""
echo "==> Setting GitHub Actions variables on ${TALK_GITHUB_APP_REPO}"

gh variable set ACR_NAME    --repo "$TALK_GITHUB_APP_REPO" --body "$TALK_ACR_NAME"
gh variable set GITOPS_REPO --repo "$TALK_GITHUB_APP_REPO" --body "$TALK_GITHUB_GITOPS_REPO"

echo "    Set ACR_NAME=${TALK_ACR_NAME}, GITOPS_REPO=${TALK_GITHUB_GITOPS_REPO}"

# ── 4. Update and register Argo CD Applications ─────────────────────
echo ""
echo "==> Updating Argo CD Application manifests for ${TALK_ENV}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="${REPO_ROOT}/argocd-applications/${TALK_ENV}"

if [ -d "$APP_DIR" ]; then
  for f in "$APP_DIR"/*.yaml; do
    sed -i.bak "s|repoURL:.*|repoURL: ${GITOPS_REPO_URL}|" "$f"
    rm -f "${f}.bak"
  done
  echo "    Updated repoURL in argocd-applications/${TALK_ENV}/"

  kubectl apply -f "$APP_DIR/"
  echo "    Applied manifests from argocd-applications/${TALK_ENV}/"
else
  echo "    WARNING: ${APP_DIR} not found. Create Argo CD Application manifests first."
fi

echo ""
echo "==> CI/CD setup complete."
echo ""
echo "Next steps:"
echo "  1. Push code to the '${TALK_ENV}' branch of ${TALK_GITHUB_APP_REPO}"
echo "  2. GitHub Actions will build images, push to ACR, and update gitops tags"
echo "  3. Argo CD will auto-deploy the new images"

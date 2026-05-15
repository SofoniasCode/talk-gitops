#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

need_crd() {
  if ! kubectl get crd "$1" >/dev/null 2>&1; then
    echo "missing required CRD: $1" >&2
    echo "Install External Secrets Operator and Envoy Gateway first." >&2
    exit 1
  fi
}

need_crd externalsecrets.external-secrets.io
need_crd clustersecretstores.external-secrets.io
need_crd httproutes.gateway.networking.k8s.io
need_crd gateways.gateway.networking.k8s.io
need_crd gatewayclasses.gateway.networking.k8s.io
need_crd envoyproxies.gateway.envoyproxy.io

ensure_local_coredns_rewrite() {
  kubectl -n kube-system get configmap coredns -o json | python3 -c '
import json
import sys

configmap = json.load(sys.stdin)
rewrite = "    rewrite name exact zitadel.localhost zitadel.talk-local.svc.cluster.local\n"
corefile = configmap["data"]["Corefile"]
if rewrite not in corefile:
    corefile = corefile.replace(".:53 {\n", ".:53 {\n" + rewrite, 1)

print(
    json.dumps(
        {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {
                "name": "coredns",
                "namespace": "kube-system",
            },
            "data": {
                "Corefile": corefile,
            },
        }
    )
)
' | kubectl apply -f -
  kubectl -n kube-system rollout restart deploy/coredns
  kubectl -n kube-system rollout status deploy/coredns --timeout=60s
}

kubectl apply -k "$ROOT_DIR/platform-components/overlays/local-dev"
ensure_local_coredns_rewrite

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to check and seed local Vault" >&2
  exit 1
fi

if ! curl --fail --silent --show-error \
  "${VAULT_ADDR:-http://127.0.0.1:8200}/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204" >/dev/null; then
  echo "localhost Vault is not reachable. Start your local Vault before continuing." >&2
  exit 1
fi

if command -v pg_isready >/dev/null 2>&1; then
  pg_isready -h "${TALK_LOCAL_POSTGRES_HOST:-127.0.0.1}" -p "${TALK_LOCAL_POSTGRES_PORT:-5432}" || {
    echo "localhost Postgres is not reachable. Start your local Postgres before continuing." >&2
    exit 1
  }
fi

if command -v createdb >/dev/null 2>&1; then
  "$ROOT_DIR/scripts/prepare-local-postgres.sh"
else
  echo "createdb is not available; ensure t_authz and ${TALK_ZITADEL_DATABASE_NAME:-t_zitadel} exist in localhost Postgres." >&2
fi

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}" \
VAULT_TOKEN="${VAULT_TOKEN:-root}" \
"$ROOT_DIR/scripts/write-local-vault-secrets.sh"

kubectl apply -k "$ROOT_DIR/services/overlays/local-dev"
kubectl apply -k "$ROOT_DIR/apps/overlays/local-dev"
kubectl apply -f "$ROOT_DIR/gateway/overlays/local-dev/external-secrets.yaml" -n talk-local
kubectl -n talk-local wait --for=condition=Ready externalsecret/oauth2-proxy-oidc --timeout=60s
kubectl -n talk-local wait --for=create secret/oauth2-proxy-oidc --timeout=60s
kubectl apply -k "$ROOT_DIR/gateway/overlays/local-dev"

echo "local dev manifests applied"
echo "Add 127.0.0.1 talk.localhost zitadel.localhost to /etc/hosts if your local DNS does not resolve them."

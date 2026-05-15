#!/usr/bin/env sh
set -eu

: "${ENVOY_GATEWAY_HELM_VERSION:=v0.0.0-latest}"

helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true

if helm -n kong status kong >/dev/null 2>&1; then
  helm -n kong uninstall kong
fi

helm template envoy-gateway-crds oci://docker.io/envoyproxy/gateway-crds-helm \
  --version "$ENVOY_GATEWAY_HELM_VERSION" \
  --set crds.gatewayAPI.enabled=true \
  --set crds.gatewayAPI.channel=standard \
  --set crds.envoyGateway.enabled=true \
  | kubectl apply --server-side --force-conflicts -f -

helm upgrade --install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_HELM_VERSION" \
  --namespace envoy-gateway-system \
  --create-namespace \
  --skip-crds

kubectl -n external-secrets rollout status deploy/external-secrets --timeout=180s
kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s

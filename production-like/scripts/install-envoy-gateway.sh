#!/usr/bin/env bash
set -euo pipefail
# Install Envoy Gateway controller WITHOUT clobbering the Gateway API CRDs that
# may already be installed by another controller (e.g. Traefik). The chart bundles
# Gateway API CRDs in crds/, which a ValidatingAdmissionPolicy may reject when the
# cluster already has a newer/standard Gateway API version. We therefore:
#   1. apply ONLY Envoy Gateway's own CRDs (gateway.envoyproxy.io group), and
#   2. install the controller with --skip-crds.
# Pin the chart version for a reproducible benchmark.
EG_VERSION="${EG_VERSION:-v1.5.4}"
NS="${NS:-envoy-gateway-system}"
command -v helm >/dev/null || { echo 'helm required'; exit 1; }
command -v kubectl >/dev/null || { echo 'kubectl required'; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
helm pull oci://docker.io/envoyproxy/gateway-helm --version "$EG_VERSION" --untar --untardir "$tmp"

# 1. Envoy Gateway's own CRDs only (gateway.envoyproxy.io). Server-side apply: schemas are large.
kubectl apply --server-side -f "$tmp/gateway-helm/crds/generated/"

# 2. Controller, skipping the bundled Gateway API CRDs.
helm upgrade --install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
  --version "$EG_VERSION" \
  --namespace "$NS" --create-namespace \
  --skip-crds --wait --timeout 8m

# 3. GatewayClass used by the benchmark manifests (production-like/01-gateways.yaml).
kubectl apply -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-dev
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
YAML

kubectl -n "$NS" rollout status deployment/envoy-gateway --timeout=180s
kubectl get gatewayclass envoy-dev
echo 'Envoy Gateway ready. GatewayClass envoy-dev Accepted should be True.'

#!/usr/bin/env bash
set -euo pipefail
# Install Envoy Gateway controller WITHOUT clobbering the Gateway API CRDs that
# may already be installed by another controller (e.g. Traefik). The chart bundles
# Gateway API CRDs in crds/, which a ValidatingAdmissionPolicy may reject when the
# cluster already has a newer/standard Gateway API version. We therefore:
#   1. apply ONLY Envoy Gateway's own CRDs (gateway.envoyproxy.io group), and
#   2. install the controller with --skip-crds.
# Pin the chart version for a reproducible benchmark.
EG_VERSION="${EG_VERSION:-v1.10.0}"
NS="${NS:-envoy-gateway-system}"
command -v helm >/dev/null || { echo 'helm required'; exit 1; }
command -v kubectl >/dev/null || { echo 'kubectl required'; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
helm pull oci://docker.io/envoyproxy/gateway-helm --version "$EG_VERSION" --untar --untardir "$tmp"

# 1. Envoy Gateway's own CRDs only (gateway.envoyproxy.io). Server-side apply: schemas are large.
#    The generated-CRD dir moved between chart versions (<=v1.5: crds/generated/,
#    >=v1.10: charts/crds/crds/generated/), so locate it.
GEN_DIR="$(dirname "$(find "$tmp/gateway-helm" -path '*generated*gateway.envoyproxy.io_backends.yaml' | head -1)")"
[ -n "$GEN_DIR" ] || { echo 'Could not find gateway.envoyproxy.io CRDs in chart' >&2; exit 1; }
kubectl apply --server-side -f "$GEN_DIR/"

# 2. Controller only; do NOT install any CRDs via helm so the cluster's existing Gateway API
#    CRDs stay as-is. --skip-crds covers the special crds/ dir (<=v1.5); crds.enabled=false
#    covers the CRD subchart (>=v1.10).
helm upgrade --install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
  --version "$EG_VERSION" \
  --namespace "$NS" --create-namespace \
  --skip-crds --set crds.enabled=false --wait --timeout 8m

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

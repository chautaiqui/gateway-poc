#!/usr/bin/env bash
set -euo pipefail
command -v kubectl >/dev/null || { echo 'kubectl required'; exit 1; }
command -v helm >/dev/null || { echo 'helm required'; exit 1; }
kubectl cluster-info >/dev/null
kubectl get gatewayclass envoy-dev traefik-poc
kubectl get crd backendtrafficpolicies.gateway.envoyproxy.io middlewares.traefik.io httproutes.gateway.networking.k8s.io
helm status traefik-poc -n traefik-poc >/dev/null
echo 'Preflight OK. Verify Envoy Gateway v1.9 compatibility and Traefik helm version manually.'

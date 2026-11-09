#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if ! command -v helm >/dev/null || ! command -v kubectl >/dev/null; then
  echo 'helm and kubectl are required' >&2; exit 1
fi
kubectl cluster-info >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add traefik https://traefik.github.io/charts --force-update
helm repo update
# Prometheus Operator CRDs must exist before Traefik generates ServiceMonitor.
helm upgrade --install traefik-monitoring prometheus-community/kube-prometheus-stack \
  --namespace traefik-monitoring --create-namespace \
  -f monitoring/values.yaml --wait --timeout 10m
kubectl apply -f monitoring/grafana/dashboard-configmap.yaml
# Upgrades only this named Helm release. Does not touch Envoy Gateway.
helm upgrade --install traefik-poc traefik/traefik \
  --namespace traefik-poc --create-namespace \
  -f helm/values.yaml --wait --timeout 10m
printf '\nReady. Run: bash scripts/monitoring-status.sh\n'

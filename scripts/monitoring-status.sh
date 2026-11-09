#!/usr/bin/env bash
set -euo pipefail
kubectl -n traefik-poc get deploy,svc,servicemonitor,ingressroute || true
kubectl -n traefik-monitoring get pods,svc
printf '\nTraefik dashboard: bash scripts/open-dashboard.sh\n'
printf 'Grafana: bash scripts/open-grafana.sh\n'
printf 'Prometheus: kubectl -n traefik-monitoring port-forward svc/traefik-monitoring-kube-prometheus 9090:9090\n'
printf 'Prometheus target check: up{namespace="traefik-poc"} == 1\n'

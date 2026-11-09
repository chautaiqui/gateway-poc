#!/usr/bin/env bash
set -euo pipefail
kubectl get gatewayclass envoy-dev traefik-poc
kubectl -n gateway-bench get gateway,httproute,backendtrafficpolicy,middleware,svc,pods
kubectl -n gateway-bench describe httproute envoy-bench traefik-bench
kubectl -n gateway-bench describe gateway envoy-bench traefik-bench

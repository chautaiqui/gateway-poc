#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:-baseline}"
if [[ "$MODE" != baseline && "$MODE" != production ]]; then echo 'Usage: deploy.sh baseline|production' >&2; exit 2; fi
cd "$ROOT"
bash production-like/scripts/preflight.sh
kubectl apply -f production-like/00-namespace-backend.yaml
# Self-signed TLS certificate, lab only. Never use this for public traffic.
if ! kubectl -n gateway-bench get secret bench-tls >/dev/null 2>&1; then
 command -v openssl >/dev/null || { echo 'openssl required'; exit 1; }
 tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
 openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 7    -keyout "$tmp/tls.key" -out "$tmp/tls.crt"    -subj '/CN=bench.dev.local' -addext 'subjectAltName=DNS:bench.dev.local' >/dev/null 2>&1
 kubectl -n gateway-bench create secret tls bench-tls --key="$tmp/tls.key" --cert="$tmp/tls.crt"
fi
kubectl apply -f production-like/01-gateways.yaml
kubectl apply -f production-like/02-routes.yaml
if [[ "$MODE" == production ]]; then
 kubectl apply -f production-like/policies/02-traefik.yaml
 kubectl apply -f production-like/policies/01-envoy.yaml
 kubectl apply -f production-like/policies/03-traefik-route-with-middleware.yaml
else
 kubectl -n gateway-bench delete backendtrafficpolicy envoy-bench-policies --ignore-not-found
fi
kubectl -n gateway-bench rollout status deployment/echo --timeout=180s
kubectl -n gateway-bench get gateways,httproutes,backendtrafficpolicies,middlewares
printf '\nMODE=%s. Check status conditions and test HTTPS using scripts/smoke.sh.\n' "$MODE"

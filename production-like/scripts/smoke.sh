#!/usr/bin/env bash
set -euo pipefail
# Set ENVOY_IP / TRAEFIK_IP and optional ports after inspecting Gateway addresses and Services.
# For a local service port-forward, set target IP to 127.0.0.1 and corresponding local port.
: "${ENVOY_IP:?set ENVOY_IP}" "${TRAEFIK_IP:?set TRAEFIK_IP}"
ENVOY_PORT="${ENVOY_PORT:-443}"; TRAEFIK_PORT="${TRAEFIK_PORT:-443}"
for x in envoy traefik; do
 if [[ "$x" == envoy ]]; then ip="$ENVOY_IP"; port="$ENVOY_PORT"; else ip="$TRAEFIK_IP"; port="$TRAEFIK_PORT"; fi
 echo "Testing $x at $ip:$port"
 curl --silent --show-error --fail --insecure --resolve "bench.dev.local:$port:$ip"   "https://bench.dev.local:$port/" | head -c 300
 echo
 done
kubectl -n gateway-bench get httproutes -o yaml | grep -E 'type: (Accepted|ResolvedRefs)|status: (True|False)' || true

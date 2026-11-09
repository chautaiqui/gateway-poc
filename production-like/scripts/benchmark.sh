#!/usr/bin/env bash
set -euo pipefail
# Use same generator host, duration, concurrency and backend for both gateways.
# Requires hey installed on load-generator host. Sequential tests only.
command -v hey >/dev/null || { echo 'Install hey on load-generator host'; exit 1; }
: "${ENVOY_URL:?e.g. https://bench.dev.local:9443/}" "${TRAEFIK_URL:?e.g. https://bench.dev.local:9444/}"
CONCURRENCIES="${CONCURRENCIES:-100 500 1000}"
DURATION="${DURATION:-300s}"
OUT="${OUT:-results/production-like-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
# Self-signed lab TLS uses -disable-keepalive? No: keep-alive on to simulate real clients.
# hey -disable-compression not used. Use DNS or /etc/hosts to resolve bench.dev.local.
for c in $CONCURRENCIES; do
 for target in envoy traefik; do
  if [[ "$target" == envoy ]]; then url="$ENVOY_URL"; else url="$TRAEFIK_URL"; fi
  echo "Running $target, concurrency=$c, duration=$DURATION"
  hey -disable-redirects -disable-keepalive=false -insecure -c "$c" -z "$DURATION" "$url"    > "$OUT/${target}-c${c}.txt"
  sleep "${COOLDOWN:-30}"
 done
done
printf 'Results: %s\n' "$OUT"

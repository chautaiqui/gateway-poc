#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${BASE_URL:-http://127.0.0.1:18080}"
check() { local host="$1" expected="$2"; local code; code=$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: $host" "$BASE_URL/"); echo "$host -> $code (expected $expected)"; [[ "$code" == "$expected" ]]; }
check echo.traefik.test 200
check weighted.traefik.test 200
check redirect.traefik.test 301
check headers.traefik.test 200
headers=$(curl -sS -D - -o /dev/null -H 'Host: headers.traefik.test' "$BASE_URL/")
echo "$headers" | grep -qi 'X-Poc-Response: traefik'
echo 'Smoke tests passed (rate-limit behavior requires burst test).'

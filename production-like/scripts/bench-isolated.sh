#!/usr/bin/env bash
set -euo pipefail
# Isolated side-by-side benchmark: bench ONE gateway at a time with the OTHER scaled to 0,
# so the idle controller/proxy adds no CPU noise or node contention. For each gateway and
# concurrency it records hey throughput/latency/status plus Prometheus-sourced CPU & RAM of
# the data-plane pods, appended as rows to a CSV.
#
# Requires: kubectl, helm, hey, curl, python3. Run from repo root or anywhere.
# Env:
#   CONCURRENCIES   space-separated list      (default "50 200 500")
#   DURATION_S      seconds per run           (default 20)
#   WARMUP_S        warmup seconds per gw     (default 5)
#   COOLDOWN_S      sleep between runs        (default 8)
#   REPLICAS        replicas for active gw    (default 1, applied to both for fairness)
#   OUT_CSV         results CSV path          (default docs/benchmark-results.csv)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONCURRENCIES="${CONCURRENCIES:-50 200 500}"
DURATION_S="${DURATION_S:-20}"
WARMUP_S="${WARMUP_S:-5}"
COOLDOWN_S="${COOLDOWN_S:-8}"
REPLICAS="${REPLICAS:-1}"
OUT_CSV="${OUT_CSV:-$ROOT/docs/benchmark-results.csv}"
HOST="bench.dev.local"
NS_BENCH="gateway-bench"
NS_ENVOY="envoy-gateway-system"
NS_TRAEFIK="traefik-poc"
PROM_SVC="traefik-monitoring-kube-pr-prometheus"
NS_MON="traefik-monitoring"

for b in kubectl hey curl python3; do command -v "$b" >/dev/null || { echo "$b required" >&2; exit 1; }; done

ENVOY_DEP="$(kubectl -n "$NS_ENVOY" get deploy -l gateway.envoyproxy.io/owning-gateway-name=envoy-bench -o jsonpath='{.items[0].metadata.name}')"
[ -n "$ENVOY_DEP" ] || { echo 'Envoy proxy deployment not found; deploy baseline first' >&2; exit 1; }
ENVOY_VER="$(kubectl -n "$NS_ENVOY" get deploy "$ENVOY_DEP" -o jsonpath='{.spec.template.spec.containers[?(@.name=="envoy")].image}' | sed 's/.*://')"
TRAEFIK_VER="$(kubectl -n "$NS_TRAEFIK" get deploy traefik-poc -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')"

# Prometheus access via background port-forward.
kubectl -n "$NS_MON" port-forward "svc/$PROM_SVC" 9090:9090 >/tmp/bench-prom.log 2>&1 &
PROM_PF=$!
cleanup() { kill "$PROM_PF" "${APP_PF:-}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 4
PROM="http://127.0.0.1:9090"

prom_scalar() { # $1 = promql ; prints a number or 0
  curl -s --data-urlencode "query=$1" "$PROM/api/v1/query" \
    | python3 -c "import sys,json;
try:
 d=json.load(sys.stdin); r=d['data']['result']; print(float(r[0]['value'][1]) if r else 0)
except Exception: print(0)"
}

mkdir -p "$(dirname "$OUT_CSV")"
if [ ! -f "$OUT_CSV" ]; then
  echo "timestamp,gateway,version,replicas,concurrency,duration_s,requests_total,rps,p50_ms,p95_ms,p99_ms,status_2xx,status_non2xx,errors,cpu_cores_max,mem_mb_max" > "$OUT_CSV"
fi

scale_envoy() { kubectl -n "$NS_ENVOY" scale deploy "$ENVOY_DEP" --replicas="$1" >/dev/null; }
scale_traefik() { kubectl -n "$NS_TRAEFIK" scale deploy traefik-poc --replicas="$1" >/dev/null; }

run_gateway() { # $1 gateway name, $2 local port, $3 cpu promql, $4 mem promql
  local gw="$1" port="$2" cpu_q="$3" mem_q="$4"
  # Connect to the port-forward on localhost; carry the vhost in the Host header via hey -host.
  local url="http://127.0.0.1:$port/"
  echo "### Benchmarking $gw (other gateway scaled to 0, $gw replicas=$REPLICAS) ###"
  # port-forward the active gateway's HTTP data plane (Envoy listener :80, Traefik web :80)
  if [ "$gw" = envoy ]; then
    local svc; svc="$(kubectl -n "$NS_ENVOY" get svc -l gateway.envoyproxy.io/owning-gateway-name=envoy-bench -o jsonpath='{.items[0].metadata.name}')"
    kubectl -n "$NS_ENVOY" port-forward "svc/$svc" "$port:80" >/tmp/bench-app.log 2>&1 & APP_PF=$!
  else
    kubectl -n "$NS_TRAEFIK" port-forward svc/traefik-poc "$port:80" >/tmp/bench-app.log 2>&1 & APP_PF=$!
  fi
  sleep 4
  # warmup
  hey -host "$HOST" -c 20 -z "${WARMUP_S}s" "$url" >/dev/null 2>&1 || true
  for c in $CONCURRENCIES; do
    echo "  -> $gw c=$c for ${DURATION_S}s"
    local rawfile="/tmp/bench-raw-${gw}-c${c}.txt"
    hey -host "$HOST" -c "$c" -z "${DURATION_S}s" "$url" >"$rawfile" 2>/tmp/bench-raw-${gw}-c${c}.err || true
    # CPU/RAM max over the just-finished window
    local win="${DURATION_S}s"
    local cpu mem; cpu="$(prom_scalar "max_over_time((${cpu_q})[${win}:5s])")"; mem="$(prom_scalar "max_over_time((${mem_q})[${win}:5s])")"
    python3 - "$gw" "$ENVOY_VER" "$TRAEFIK_VER" "$REPLICAS" "$c" "$DURATION_S" "$cpu" "$mem" "$OUT_CSV" "$rawfile" <<'PY'
import sys,re,datetime
gw,ever,tver,repl,c,dur,cpu,mem,out,rawfile=sys.argv[1:11]
raw=open(rawfile).read()
ver=ever if gw=='envoy' else tver
def num(pat,default='0'):
    m=re.search(pat,raw); return m.group(1) if m else default
rps=num(r'Requests/sec:\s+([\d.]+)')
def lat(p):
    m=re.search(rf'\n\s+{p}%% in ([\d.]+) secs',raw) or re.search(rf'{p}%\s+in\s+([\d.]+) secs',raw)
    return str(round(float(m.group(1))*1000,3)) if m else '0'
p50,p95,p99=lat(50),lat(95),lat(99)
# status codes
two=0; non=0
for code,cnt in re.findall(r'\[(\d{3})\]\s+(\d+) responses',raw):
    cnt=int(cnt)
    if code.startswith('2'): two+=cnt
    else: non+=cnt
# total requests = sum of all responses
total_req=two+non
# errors section
errs=0
me=re.search(r'Error distribution:(.*)$',raw,re.S)
if me:
    for n in re.findall(r'\[(\d+)\]',me.group(1)): errs+=int(n)
cpu_r=round(float(cpu),4); mem_mb=round(float(mem)/1048576,2)
ts=datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
row=f"{ts},{gw},{ver},{repl},{c},{dur},{total_req},{rps},{p50},{p95},{p99},{two},{non},{errs},{cpu_r},{mem_mb}\n"
open(out,'a').write(row)
sys.stderr.write('     '+row)
PY
    sleep "$COOLDOWN_S"
  done
  kill "$APP_PF" >/dev/null 2>&1 || true; APP_PF=""
  sleep 2
}

# CPU / RAM PromQL per gateway (data-plane pods only)
ENVOY_CPU='sum(rate(container_cpu_usage_seconds_total{namespace="'"$NS_ENVOY"'",pod=~"'"$ENVOY_DEP"'.*",container="envoy"}[30s]))'
ENVOY_MEM='sum(container_memory_working_set_bytes{namespace="'"$NS_ENVOY"'",pod=~"'"$ENVOY_DEP"'.*",container="envoy"})'
TRAEFIK_CPU='sum(rate(container_cpu_usage_seconds_total{namespace="'"$NS_TRAEFIK"'",pod=~"traefik-poc-.*",container="traefik-poc"}[30s]))'
TRAEFIK_MEM='sum(container_memory_working_set_bytes{namespace="'"$NS_TRAEFIK"'",pod=~"traefik-poc-.*",container="traefik-poc"})'

echo '== Phase 1: bench ENVOY, Traefik OFF =='
scale_traefik 0
scale_envoy "$REPLICAS"
kubectl -n "$NS_ENVOY" rollout status deploy/"$ENVOY_DEP" --timeout=120s
run_gateway envoy 9443 "$ENVOY_CPU" "$ENVOY_MEM"

echo '== Phase 2: bench TRAEFIK, Envoy OFF =='
scale_envoy 0
scale_traefik "$REPLICAS"
kubectl -n "$NS_TRAEFIK" rollout status deploy/traefik-poc --timeout=120s
run_gateway traefik 9444 "$TRAEFIK_CPU" "$TRAEFIK_MEM"

echo '== Restore both gateways to ON =='
scale_envoy "$REPLICAS"; scale_traefik 2
echo "Results written to $OUT_CSV"
column -s, -t "$OUT_CSV" || cat "$OUT_CSV"

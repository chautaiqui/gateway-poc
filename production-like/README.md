# Production-like side-by-side benchmark (Envoy Gateway vs Traefik OSS)

**Status:** implementation manifests; NOT executed against your Kubernetes cluster. This is a controlled lab, not production-ready hardening.

## Scope and safeguards

- Existing Envoy Gateway **v1.9**, GatewayClass **`envoy-dev`** must be installed and running; no overwrite of Envoy releases.
- Existing Traefik helm release **`traefik-poc`** in namespace **`traefik-poc`**, CRD provider and Gateway provider enabled; GatewayClass **`traefik-poc`** must exist.
- Both gateways and shared 4-replica whoami backend are isolated in namespace **`gateway-bench`**.
- Both hostnames `bench.dev.local`; Envoy HTTPS listener **443**, Traefik HTTPS listener **8443** (Traefik Service exposes 443→8443). Ports must match the controller entrypoint. If gateway data plane uses a different Service/port, discover it first.
- Self-signed certificate (7 days), generated with OpenSSL. Curl `-k` for development ONLY.
- Rate limits are **local/per proxy replica** and differ in burst handling, hence not equivalent at the millisecond level.
- Traefik Retry generally retries failed *connections*, not arbitrary upstream HTTP 503. Envoy HTTP 503 retry configured here has different semantics. This means a production-like end-to-end score is informative but **not a fully apples-to-apples policy test**. Run baseline separately.
- HTTPRoute timeouts capability depends on Traefik/Kubernetes Gateway API versions; ensure route `Accepted=True`, `ResolvedRefs=True`, and test a slow backend before claiming parity.
- Do not run original `labs/` and this overlay as a single feature demo; separate namespaces, hosts and policies.

## Install Envoy Gateway (if not already present)

If the cluster has no Envoy Gateway yet, install it without clobbering existing Gateway API CRDs:

```bash
bash production-like/scripts/install-envoy-gateway.sh   # applies envoyproxy.io CRDs, controller, GatewayClass envoy-dev
```

This skips the chart's bundled Gateway API CRDs (kept at the cluster's existing version) and
creates GatewayClass `envoy-dev`. Pin `EG_VERSION` for reproducibility.

## Automated isolated benchmark ("turn one off while benchmarking the other")

`scripts/bench-isolated.sh` benchmarks each gateway with the **other scaled to 0 replicas**,
pins the active gateway to 1 replica, drives load with `hey` over the plain-HTTP listener, and
appends throughput/latency/status plus Prometheus-sourced CPU & RAM to `docs/benchmark-results.csv`:

```bash
CONCURRENCIES='50 200 500' DURATION_S=20 bash production-like/scripts/bench-isolated.sh
```

Results summary: [../docs/benchmark-results.md](../docs/benchmark-results.md). Both gateways
expose an extra plain-HTTP listener (Envoy :80, Traefik :8000 → Service :80) so a `hey` build
without `-insecure` can benchmark without TLS trust. HTTPS listeners remain for functional tests.

## Run

```bash
# 1. Optional: upgrade Traefik workload to benchmark resources; don't overwrite another Helm release.
helm upgrade traefik-poc traefik/traefik -n traefik-poc \
  -f helm/values.yaml -f production-like/helm/traefik-values-overlay.yaml

# 2. Test controller and CRD readiness; no modifications here
bash production-like/scripts/preflight.sh

# 3. Baseline: shared backend + TLS + routing + timeouts; no retry or rate limit
bash production-like/scripts/deploy.sh baseline
bash production-like/scripts/status.sh

# 4. Full production-like: apply middleware and BTP
bash production-like/scripts/deploy.sh production
bash production-like/scripts/status.sh

# 5. Identify actual data-plane service addresses
kubectl -n gateway-bench get gateway -o wide
kubectl -n envoy-gateway-system get svc
kubectl -n traefik-poc get svc

# 6. HTTPS connectivity; ENV IP and TRAEFIK IP must be reachable from current host
ENVOY_IP=10.0.0.1 TRAEFIK_IP=10.0.0.2 bash production-like/scripts/smoke.sh
```

**Important:** With Traefik Service type ClusterIP, access via port-forward or from a cluster Pod. For Envoy, use the *actual* Service generated for `gateway-bench/envoy-bench`, not the existing `ads-gateway` IP unless you have verified it is the correct route.

Example Traefik port-forward (adjust service name using `kubectl get svc`):

```bash
kubectl -n traefik-poc port-forward svc/traefik-poc 9444:443
# With /etc/hosts bench.dev.local => 127.0.0.1:
curl -k https://bench.dev.local:9444/
```

For Envoy, discover generated Service and port-forward it to local 9443, then verify:

```bash
curl -k https://bench.dev.local:9443/
```

## Monitoring

Envoy is wired into the SAME kube-prometheus-stack as Traefik by `../monitoring/envoy/scrape.yaml`
(a PodMonitor for the Envoy proxy `/stats/prometheus` + a ServiceMonitor for the controller
`/metrics`, both carrying `release: traefik-monitoring` so the shared Prometheus selects them):

```bash
kubectl apply -f monitoring/envoy/scrape.yaml   # from repo root
```

A combined Grafana dashboard **Gateway Benchmark: Envoy vs Traefik** (`../monitoring/grafana/comparison-dashboard.yaml`,
uid `gateway-bench-compare`) overlays RPS, 5xx, p95/p99, CPU, RAM and active connections for both.
Confirm all targets are UP in Prometheus **Status > Targets** (same 15s interval) before trusting panels.

Must record: successful requests/sec, 2xx/4xx/5xx/429, p50/p95/p99, Envoy/Traefik CPU and RSS, backend CPU, active connections, generator saturation, dropped requests. **503 responses previously observed should be split by origin** (gateway vs backend vs load-generator failure) before ranking.

## Benchmark execution

1. Pin chart/image versions in your environment, export Helm values and commit generated lockfile or version record.
2. Disable HPA and ensure equal replica counts and CPU/RAM constraints; verify Envoy Proxy generated deployment specs independently (this overlay only sets Traefik resources).
3. Use identical backend, response payload, TLS cipher, client connection reuse, access log and tracing settings; exclude test traffic other than benchmark.
4. For **capacity/RPS tests**, run baseline with no rate limit; production-like with 10k r/s per replica intentionally measures policy behavior and cannot be used as a pure max-RPS comparison.
5. Run 60s warmup, >= 3 repetitions for each concurrency, swap gateway order between trials and allow cooldown.
6. Use `hey` with identical flags, from an *external* load generator separate from the backend; DNS must resolve `bench.dev.local` to appropriate endpoint. `-insecure` bypasses cert verification for lab cert.

```bash
export ENVOY_URL=https://bench.dev.local:9443/
export TRAEFIK_URL=https://bench.dev.local:9444/
export CONCURRENCIES='100 500 1000 4000'
export DURATION=300s
bash production-like/scripts/benchmark.sh
```

**Caution:** `hey` may not provide identical TLS/HTTP2 semantics as desired. Confirm protocol through capture/headers; use dedicated h2load for HTTP/2. Connections/ports and local CPU may become the bottleneck above concurrency 1000. For a clean comparison, run separate 503/retry injection tests, not the happy-path echo throughput test.

## Rollback/cleanup

```bash
kubectl -n gateway-bench delete backendtrafficpolicy envoy-bench-policies --ignore-not-found
kubectl -n gateway-bench delete middleware bench-retry bench-ratelimit --ignore-not-found
# Remove ONLY lab namespace. Does not touch existing Envoy Gateway controllers.
kubectl delete namespace gateway-bench
```

## Known limitations

- Session affinity, distributed rate limiting, JWT and WAF are **not** activated.
- External TLS validation, real ingress LB, Kubernetes PDB/HA spread, HPA, cert rotation, retry budgets and full security review are **not** implemented.
- For strict side-by-side retry comparison, use failures of the same class (connect/reset); do not compare HTTP 503 retry as feature parity.
- The `GatewayClass` preflight assumes the previously documented cluster names; edit for different installations.

Sources: https://gateway.envoyproxy.io/v1.9/tasks/traffic/local-rate-limit/ ; https://gateway.envoyproxy.io/v1.9/tasks/traffic/retry/ ; https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/

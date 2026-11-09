# Benchmark results — Envoy Gateway vs Traefik OSS

Raw rows: [benchmark-results.csv](benchmark-results.csv). Regenerate with
`bash production-like/scripts/bench-isolated.sh`. Live comparison: Grafana dashboard
**Gateway Benchmark: Envoy vs Traefik** (uid `gateway-bench-compare`).

## Setup (as run 2026-11-10, latest stable each)

- Cluster: 3-node kind (`traefik-poc` control-plane + 2 workers).
- Envoy Gateway **v1.10.0** (proxy image Envoy `distroless-v1.40.2`), GatewayClass `envoy-dev`.
- Traefik OSS **v3.7.17** (chart 42.3.1, the latest), GatewayClass `traefik-poc`.
- Shared backend: `traefik/whoami` ×4 in ns `gateway-bench`; both gateways route to it.
- Load over **plain HTTP** (listener added alongside HTTPS) to remove TLS-handshake variance;
  generated with `hey` through `kubectl port-forward` from the same host.
- **Isolation:** each gateway benchmarked with the OTHER scaled to 0 replicas, and the
  active gateway pinned to **1 replica** for a per-replica, apples-to-apples comparison.
- Monitoring: one kube-prometheus-stack scrapes BOTH gateways (Envoy proxy PodMonitor +
  controller ServiceMonitor, Traefik ServiceMonitor). CPU/RAM are the max over each run window.

## Results (1 replica each, 20s per run)

| Gateway | Conc. | RPS | p50 (ms) | p95 (ms) | p99 (ms) | 2xx | non-2xx | CPU (cores)* | Mem (MB) |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| Envoy   | 50  | 21,976 | 2.1 | 3.8 | 5.6 | 439,556 | 0 | ~2.2 | 29.2 |
| Envoy   | 200 | 28,934 | 6.3 | 12.4 | 16.6 | 578,837 | 0 | ~2.25 | 42.5 |
| Envoy   | 500 | 34,374 | 13.6 | 24.9 | 31.8 | 687,873 | 0 | ~2.25 | 66.0 |
| Traefik | 50  | 15,067 | 2.9 | 6.7 | 9.4 | 301,384 | 0 | ~1.2 | 87.7 |
| Traefik | 200 | 14,694 | 12.6 | 24.0 | 29.4 | 294,026 | 0 | ~1.37 | 129.1 |
| Traefik | 500 | 14,387 | 34.0 | 49.3 | 58.7 | 288,037 | 0 | ~1.37 | 204.3 |

\* CPU is a smoothed `rate[1m]` peak and is approximate (cAdvisor scrape ≈30s vs 20s runs); treat
it as order-of-magnitude only. Memory (working set) is a reliable gauge.

## Observations (this lab only)

- **Throughput:** Envoy scaled up with concurrency (22k → 34k RPS); Traefik held ~14–15k RPS.
- **Latency:** comparable at c=50; Envoy stayed lower at higher concurrency (p99 32 ms vs 59 ms at c=500).
- **Memory:** Envoy's working set was far smaller (29–66 MB vs 88–204 MB).
- **CPU vs work done:** Envoy used ~2.2 cores to push ~2.4× the RPS Traefik did at ~1.3 cores.
- **Errors:** zero non-2xx on both across all runs.

## Caveats — do NOT over-read these numbers

- Light PoC: single 20s run per point, no repeats; `kubectl port-forward` and the local `hey`
  box are likely bottlenecks above ~c=200. This is a smoke-grade comparison, not a capacity test.
- CPU figures are smoothed/approximate (see note above); memory is reliable.
- Plain HTTP only; no TLS, retry, rate-limit or HTTP/2 under load here.
- Replica counts, resource limits and chart/image versions must be pinned and runs repeated
  (see [benchmark-plan.md](benchmark-plan.md)) before any published Envoy-vs-Traefik claim.

# Benchmark results — Envoy Gateway vs Traefik OSS

Raw rows: [benchmark-results.csv](benchmark-results.csv). Regenerate with
`bash production-like/scripts/bench-isolated.sh`. Live comparison: Grafana dashboard
**Gateway Benchmark: Envoy vs Traefik** (uid `gateway-bench-compare`).

## Setup (as run 2026-11-10)

- Cluster: 3-node kind (`traefik-poc` control-plane + 2 workers).
- Envoy Gateway **v1.5.4** (proxy image `distroless-v1.35.6`), GatewayClass `envoy-dev`.
- Traefik OSS **v3.7.17** (chart 42.3.1), GatewayClass `traefik-poc`.
- Shared backend: `traefik/whoami` ×4 in ns `gateway-bench`; both gateways route to it.
- Load over **plain HTTP** (listener added alongside HTTPS) to remove TLS-handshake variance;
  generated with `hey` through `kubectl port-forward` from the same host.
- **Isolation:** each gateway benchmarked with the OTHER scaled to 0 replicas, and the
  active gateway pinned to **1 replica** for a per-replica, apples-to-apples comparison.
- Monitoring: one kube-prometheus-stack scrapes BOTH gateways (Envoy proxy PodMonitor +
  controller ServiceMonitor, Traefik ServiceMonitor). CPU/RAM are the max over each run window.

## Results (1 replica each, 20s per run)

| Gateway | Conc. | RPS | p50 (ms) | p95 (ms) | p99 (ms) | 2xx | non-2xx | CPU (cores) | Mem (MB) |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| Envoy   | 50  | 23,012 | 2.0 | 3.5 | 5.2 | 460,279 | 0 | 1.92 | 31.7 |
| Envoy   | 200 | 30,958 | 6.0 | 11.3 | 15.1 | 619,308 | 0 | 2.90 | 43.0 |
| Envoy   | 500 | 36,966 | 12.8 | 22.4 | 28.3 | 739,893 | 0 | 2.27 | 59.9 |
| Traefik | 50  | 14,812 | 2.9 | 6.8 | 9.5 | 296,278 | 0 | 1.15 | 84.2 |
| Traefik | 200 | 13,998 | 13.2 | 24.9 | 30.4 | 280,085 | 0 | 0.97 | 113.3 |
| Traefik | 500 | 13,912 | 35.2 | 50.9 | 59.8 | 278,590 | 0 | 1.75 | 211.0 |

## Observations (this lab only)

- **Throughput:** Envoy scaled up with concurrency (23k → 37k RPS); Traefik plateaued ~14k RPS.
- **Latency:** comparable at c=50; Envoy stayed lower at higher concurrency (p99 28 ms vs 60 ms at c=500).
- **Memory:** Envoy's working set was far smaller (32–60 MB vs 84–211 MB).
- **Errors:** zero non-2xx on both across all runs.

## Caveats — do NOT over-read these numbers

- Light PoC: single 20s run per point, no repeats; `kubectl port-forward` and the local `hey`
  box are likely bottlenecks above ~c=200. This is a smoke-grade comparison, not a capacity test.
- Plain HTTP only; no TLS, retry, rate-limit or HTTP/2 under load here.
- Replica counts, resource limits and chart/image versions must be pinned and runs repeated
  (see [benchmark-plan.md](benchmark-plan.md)) before any published Envoy-vs-Traefik claim.

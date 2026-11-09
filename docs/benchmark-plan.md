# Fair Envoy vs Traefik benchmark

1. Same cluster, same backend pods and resource limits; distinct GatewayClasses and dedicated gateway services.
2. Pin versions; log Kubernetes version, node placement, Helm values, CPU/RAM requests and limits.
3. Use a remote load generator (not port-forward). Warm up each test; run sequentially and randomize order.
4. Test fixed concurrency 50, 100, 250, 500, 1000, 2000; maintain the same request count or duration per run.
5. Capture RPS, p50/p95/p99, HTTP status distribution, connection errors, CPU, memory, pod restarts, backend saturation.
6. Mark any 503, 429, timeout and client-side errors separately. Compare successful throughput, not just total requests.
7. Run 3+ repeats, store raw output and manifests in versioned result folders. Do not commit secrets or raw PII logs.
8. Repeat with 1 and 2 gateway replicas; check HPA, disruption and recovery separately.

## Observability add-on

- Traefik dashboard via local port-forward confirms active routers/middlewares/services.
- Prometheus ServiceMonitor scrapes the dedicated Traefik metrics Service every 15 seconds.
- Grafana dashboard includes RPS, 5xx, response distribution, p95/p99 latency, CPU, RAM, open connections.
- Validate that Prometheus target is UP before executing a benchmark; use the same sampling/window for Envoy.
- Treat service monitor labels, benchmark request status, and backend saturation as separate evidence.

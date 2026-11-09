# Traefik Gateway API PoC — 80-feature comparison

A non-invasive Traefik OSS PoC for a Kubernetes cluster already running Envoy Gateway.

## Scope and evidence
- `docs/feature-matrix.csv`: 80 Envoy v1.9 feature names, P0–P3 priority, preliminary implementation *candidates*. **No feature is marked passed.**
- `tests/smoke.sh`: executable HTTP route, weighted split, redirect, header mutation, rate limit smoke checks. Tests are not equivalent to complete feature conformance.
- No modification to existing Envoy GatewayClass, Gateway or routes.
- Traefik-specific CRDs and external dependencies are explicitly separated from native Gateway API.

## Prerequisites
Kubernetes, kubectl, Helm 3, curl; network access to Helm chart repository. Gateway API CRDs must already be installed and compatible with Traefik version. Verify CRD versions before upgrading them; do not blindly overwrite Envoy's CRDs.

## Install
```bash
kubectl get gatewayclasses
kubectl get crd gateways.gateway.networking.k8s.io -o yaml | head
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik-poc traefik/traefik --namespace traefik-poc --create-namespace -f helm/values.yaml
kubectl apply -f base/backend.yaml
kubectl apply -f base/gateway.yaml
kubectl apply -f labs/01-http-routing.yaml
kubectl -n traefik-poc rollout status deployment/traefik-poc
kubectl -n traefik-poc port-forward svc/traefik-poc 18080:80
# in another shell
curl -i -H 'Host: echo.traefik.test' http://127.0.0.1:18080/
```

## Labs
```bash
kubectl apply -f labs/02-weighted.yaml
kubectl apply -f labs/03-redirect.yaml
kubectl apply -f labs/04-headers.yaml
kubectl apply -f labs/05-ratelimit.yaml
BASE_URL=http://127.0.0.1:18080 bash tests/smoke.sh
```

Run tests only after their corresponding manifests are applied. For production-like benchmarking, use a dedicated load generator, a consistent network path, separate exposed ports and identical backend resource limits; avoid `kubectl port-forward` for throughput benchmarking.

## Scoring
Each feature starts NOT_VERIFIED. Only change `result` to PASS after storing the manifest, command, actual response, controller/version, and logs. Use PARTIAL, FAIL, NOT_SUPPORTED, or BLOCKED for other outcomes. Do not count candidates as coverage.

## Cautions
- The Helm chart and Traefik version are not pinned here: pin chart digest/version and image before formal comparison.
- Traefik CRD middleware integration requires the Kubernetes CRD provider.
- Some advanced functions may require Traefik Hub or a separate service; OSS-only support must be verified per feature.
- Port-forward is only for functional smoke tests.
- Keep existing Envoy resources intact.

Official docs: https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/

## Traefik Dashboard + Prometheus / Grafana (patch)

The dashboard is exposed **only via local port-forward of the ClusterIP service**.
The dashboard is read-only operational visibility, not a GUI to edit Gateway API manifests.
Prometheus Operator installs separately in namespace `traefik-monitoring`; it is not a
replacement for any existing Envoy monitoring stack.

```bash
# Before installation check whether your cluster already has Prometheus Operator CRDs.
kubectl get crd servicemonitors.monitoring.coreos.com || true
# Install monitoring FIRST, so ServiceMonitor CRDs exist for the Traefik chart:
bash scripts/install-monitoring.sh
bash scripts/monitoring-status.sh

# terminal 1: browser URL http://dashboard.traefik.test:18081/dashboard/
# Add 127.0.0.1 dashboard.traefik.test to the browser machine's hosts file.
bash scripts/open-dashboard.sh

# terminal 2: browser URL http://127.0.0.1:3000
bash scripts/open-grafana.sh

# terminal 3: Prometheus http://127.0.0.1:9090
kubectl -n traefik-monitoring port-forward svc/traefik-monitoring-kube-prometheus 9090:9090
```

Grafana dashboard: **Traefik Gateway PoC / Performance**. Graphs: RPS, per-status request
rate, p95/p99, CPU, RAM, active connections, 5xx. Query `up` / inspect **Status > Targets**
first. Metric names/labels can vary by Traefik/chart version; inspect Prometheus `/api/v1/label/__name__/values`
and adjust dashboards if any panel is empty. A blank panel is **not** evidence of zero traffic.

### Restrictions / existing stack

- Namespace `traefik-monitoring` deploys a separate Prometheus Operator/Grafana; avoid installing
  another operator if you already share monitoring CRDs and want centralized monitoring.
- Monitoring stack creates cluster-scoped CRDs (and node-exporter DaemonSet). Review with cluster admin.
- Both dashboard and Grafana are internal ClusterIP services, not published on public listeners.
- Do not use port-forward for load benchmarks: use real traffic from a load generator.
- Reuse your existing Prometheus/Grafana instead if it is already installed by setting the
  appropriate ServiceMonitor label in `helm/values.yaml` and skipping installation of
  `traefik-monitoring` stack.
- Pin chart versions after validation; these example Helm install scripts use the latest compatible chart.
- Do not run `helm uninstall` against an existing monitoring release. No Envoy resources are modified.

## Side-by-side production-like benchmark

For Envoy Gateway v1.9 vs Traefik OSS with shared backend, HTTPS, timeout, retry and per-proxy local rate limiting, see [production-like/README.md](production-like/README.md). Run `bash production-like/scripts/preflight.sh` before applying any resources. Existing monitoring currently covers Traefik; Envoy scrape integration needs verification.

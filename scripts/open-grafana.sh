#!/usr/bin/env bash
set -euo pipefail
SECRET=$(kubectl -n traefik-monitoring get secret -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=traefik-monitoring -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$SECRET" ]]; then echo 'Grafana secret not found' >&2; exit 1; fi
printf 'Grafana http://127.0.0.1:3000 | username: admin\n'
printf 'Password: '
kubectl -n traefik-monitoring get secret "$SECRET" -o jsonpath='{.data.admin-password}' | base64 -d
printf '\n'
kubectl -n traefik-monitoring port-forward svc/traefik-monitoring-grafana 3000:80

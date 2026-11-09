#!/usr/bin/env bash
set -euo pipefail
printf 'Open http://127.0.0.1:18081/dashboard/ (Host header routed via localhost proxy)\n'
printf 'For browser access add temporarily to /etc/hosts: 127.0.0.1 dashboard.traefik.test\n'
printf 'Then open http://dashboard.traefik.test:18081/dashboard/\n'
printf 'This is local-only. Do not expose the dashboard Service publicly.\n'
kubectl -n traefik-poc port-forward svc/traefik-poc 18081:80

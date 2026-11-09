#!/usr/bin/env bash
set -euo pipefail
kubectl get gatewayclasses
kubectl -n traefik-poc get gateway,httproute,pods,svc
kubectl -n traefik-poc describe gateway traefik-poc

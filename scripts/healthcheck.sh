#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "${ROOT_DIR}/.env" ]] && source "${ROOT_DIR}/.env"

: "${NAMESPACE:=spark}"
: "${BASE_DOMAIN:=127.0.0.1.nip.io}"
: "${DEMO_HOST:=demo}"
: "${KEYCLOAK_HOST:=keycloak}"

kubectl -n "${NAMESPACE}" rollout status deploy/demo-app --timeout=180s
kubectl -n "${NAMESPACE}" rollout status deploy/oauth2-proxy --timeout=180s || true

echo "Demo app (protected): http://${DEMO_HOST}.${BASE_DOMAIN}"
echo "Keycloak:            http://${KEYCLOAK_HOST}.${BASE_DOMAIN}"

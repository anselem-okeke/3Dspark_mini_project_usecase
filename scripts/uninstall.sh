#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "${ROOT_DIR}/.env" ]] && source "${ROOT_DIR}/.env"

: "${NAMESPACE:=spark}"
: "${INSTALL_OBSERVABILITY:=false}"

# --- app namespace resources ---

# Bootstrap bits (explicit names; RBAC has no labels)
kubectl -n "${NAMESPACE}" delete job keycloak-bootstrap --ignore-not-found || true
kubectl -n "${NAMESPACE}" delete sa keycloak-bootstrap --ignore-not-found || true
kubectl -n "${NAMESPACE}" delete role keycloak-bootstrap --ignore-not-found || true
kubectl -n "${NAMESPACE}" delete rolebinding keycloak-bootstrap --ignore-not-found || true

# oauth2-proxy + demo ingress created via envsubst templates
kubectl -n "${NAMESPACE}" delete ingress demo-app --ignore-not-found || true
kubectl -n "${NAMESPACE}" delete deploy oauth2-proxy --ignore-not-found || true
kubectl -n "${NAMESPACE}" delete svc oauth2-proxy --ignore-not-found || true

# Demo app (deployment+service)
kubectl -n "${NAMESPACE}" delete -f "${ROOT_DIR}/k8s/10-demo-app.yaml" --ignore-not-found || true

# --- Keycloak (official) ---
kubectl -n "${NAMESPACE}" delete ingress keycloak --ignore-not-found || true
kubectl -n "${NAMESPACE}" delete deploy keycloak --ignore-not-found || true
kubectl -n "${NAMESPACE}" delete svc keycloak --ignore-not-found || true

# --- Postgres for Keycloak (official) ---
kubectl -n "${NAMESPACE}" delete sts keycloak-postgres --ignore-not-found || true
kubectl -n "${NAMESPACE}" delete svc keycloak-postgres --ignore-not-found || true

# Delete PVCs created by the keycloak-postgres StatefulSet
kubectl -n "${NAMESPACE}" delete pvc -l app=keycloak-postgres --ignore-not-found || true
# Fallback (in case labels differ)
kubectl -n "${NAMESPACE}" delete pvc -l statefulset.kubernetes.io/pod-name=keycloak-postgres-0 --ignore-not-found || true

# Secrets (official flow)
kubectl -n "${NAMESPACE}" delete secret \
  oauth2-proxy-secret \
  spark-demo-user \
  keycloak-admin \
  keycloak-db \
  spark-bootstrap \
  --ignore-not-found || true

# --- cluster-wide / other namespaces ---

# Observability (optional)
if [[ "${INSTALL_OBSERVABILITY}" == "true" ]]; then
  helm -n monitoring uninstall kube-prom || true
fi

# Ingress controller
helm -n ingress-nginx uninstall ingress-nginx || true

# Finally remove namespace
kubectl delete ns "${NAMESPACE}" --ignore-not-found || true
echo "[uninstall] done"


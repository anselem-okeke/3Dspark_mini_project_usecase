#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "${ROOT_DIR}/.env" ]] && source "${ROOT_DIR}/.env"

: "${NAMESPACE:=spark}"
: "${BASE_DOMAIN:=127.0.0.1.nip.io}"
: "${KEYCLOAK_ADMIN:=admin}"
: "${KEYCLOAK_ADMIN_PASSWORD:=admin12345}"
: "${KEYCLOAK_REALM:=spark}"
: "${DEMO_HOST:=demo}"
: "${KEYCLOAK_HOST:=keycloak}"
: "${DEMO_USER:=alice}"
: "${DEMO_USER_PASSWORD:=Password123!}"

: "${INSTALL_INGRESS:=true}"
: "${INSTALL_OBSERVABILITY:=false}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
need kubectl
need helm
need envsubst
need sed

echo "[1/8] Namespace"
kubectl apply -f "${ROOT_DIR}/k8s/00-namespace.yaml" >/dev/null

if [[ "${INSTALL_INGRESS}" == "true" ]]; then
  echo "[2/8] Ingress NGINX"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
  helm repo update >/dev/null
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    -n ingress-nginx --create-namespace \
    -f "${ROOT_DIR}/helm/values/ingress-nginx.yaml" >/dev/null

  echo "[2.5/8] Wait for ingress-nginx controller"
  kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s

  # Ensure service exist and has ClusterIP
  INGRESS_CLUSTER_IP="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')"
  if [[ -z "${INGRESS_CLUSTER_IP}" ]]; then
    echo "ERROR: ingress-nginx-controller service has no ClusterIP"
    exit 1
  fi

else
  echo "[2/8] Ingress NGINX (skipped)"
fi

# Observerbility - ServiceMonitor is a Prometheus Operator CRD that comes with kube-prometheus-stack)
#-----------------------------------------------------------------------------------------------------
if [[ "${INSTALL_OBSERVABILITY}" == "true" ]]; then
  echo "[obs] kube-prometheus-stack"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
  helm repo update >/dev/null

  TMP_OBS="$(mktemp)"
  sed "s/127\.0\.0\.1\.nip\.io/${BASE_DOMAIN}/g" \
    "${ROOT_DIR}/helm/values/kube-prom-stack.yaml" > "${TMP_OBS}"

  helm upgrade --install kube-prom prometheus-community/kube-prometheus-stack \
    -n monitoring --create-namespace \
    -f "${TMP_OBS}" >/dev/null

  rm -f "${TMP_OBS}"

  echo "[obs] ServiceMonitor for demo-app"
  kubectl apply -f "${ROOT_DIR}/k8s/20-servicemonitor-demo-app.yaml" >/dev/null
else
  echo "[obs] skipped"
fi
#-----------------------------------------------------------------------------------------------------

echo "[3/8] Demo app"
kubectl apply -f "${ROOT_DIR}/k8s/10-demo-app.yaml" >/dev/null

echo "[4/8] Keycloak (official) + Postgres (official)"

# --- DB secret for Postgres (used by k8s/15-keycloak-postgres.yaml) ---
kubectl -n "${NAMESPACE}" create secret generic keycloak-db \
  --from-literal=username="keycloak" \
  --from-literal=password="keycloakpass" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# --- Admin secret for Keycloak + bootstrap job ---
kubectl -n "${NAMESPACE}" create secret generic keycloak-admin \
  --from-literal=username="${KEYCLOAK_ADMIN}" \
  --from-literal=password="${KEYCLOAK_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# --- Deploy Postgres (official image) ---
kubectl apply -f "${ROOT_DIR}/k8s/15-keycloak-postgres.yaml" >/dev/null

echo "[4.1/8] Wait for Postgres readiness"
kubectl -n "${NAMESPACE}" rollout status sts/keycloak-postgres --timeout=900s
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l app=keycloak-postgres --timeout=900s

# --- Deploy Keycloak (official image) ---
echo "[4.2/8] Deploy Keycloak (templated) + wait readiness"

TMP_KC="$(mktemp)"
cleanup() { rm -f "${TMP_KC}" "${TMP_OBS:-}"; }
trap cleanup EXIT

# Make sure envsubst can see these variables
export BASE_DOMAIN KEYCLOAK_HOST KEYCLOAK_REALM NAMESPACE

# Render template -> real YAML (no ${...} left inside)
envsubst < "${ROOT_DIR}/k8s/18-keycloak.yaml" > "${TMP_KC}"

kubectl apply -f "${TMP_KC}" >/dev/null

echo "[5/8] Wait for Keycloak readiness"
kubectl -n "${NAMESPACE}" rollout status deploy/keycloak --timeout=1800s
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l app=keycloak --timeout=1800s


echo "[6/8] Bootstrap secrets for job"
kubectl -n "${NAMESPACE}" create secret generic spark-bootstrap \
  --from-literal=realm="${KEYCLOAK_REALM}" \
  --from-literal=base_domain="${BASE_DOMAIN}" \
  --from-literal=demo_host="${DEMO_HOST}" \
  --from-literal=demo_user="${DEMO_USER}" \
  --from-literal=demo_user_password="${DEMO_USER_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "[7/8] Keycloak realm/client/user bootstrap"
kubectl apply -f "${ROOT_DIR}/k8s/20-keycloak-bootstrap-rbac.yaml" >/dev/null
kubectl apply -f "${ROOT_DIR}/k8s/25-keycloak-bootstrap-job.yaml" >/dev/null
kubectl -n "${NAMESPACE}" wait --for=condition=complete job/keycloak-bootstrap --timeout=900s

echo "[8/8] Deploy oauth2-proxy + protected ingress"

if [[ "${INSTALL_INGRESS}" != "true" ]]; then
  echo "ERROR: INSTALL_INGRESS=false is not supported in this demo (oauth2-proxy uses INGRESS_CLUSTER_IP hostAliases)."
  exit 1
fi

export NAMESPACE BASE_DOMAIN KEYCLOAK_REALM DEMO_HOST KEYCLOAK_HOST INGRESS_CLUSTER_IP

envsubst < "${ROOT_DIR}/k8s/templates/30-oauth2-proxy.yaml" | kubectl apply -f - >/dev/null
envsubst < "${ROOT_DIR}/k8s/templates/40-demo-ingress.yaml" | kubectl apply -f - >/dev/null

echo
echo "DONE..."
echo "Keycloak: http://${KEYCLOAK_HOST}.${BASE_DOMAIN} - user:admin, password:admin12345"
echo "Demo App (protected): http://${DEMO_HOST}.${BASE_DOMAIN} - user:alice, password:Password123!"
echo "Demo user: ${DEMO_USER}"
echo "Demo password: stored in secret spark-demo-user"


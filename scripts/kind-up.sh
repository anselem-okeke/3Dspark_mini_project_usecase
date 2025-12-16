#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
need kind
need kubectl
need docker

CLUSTER_NAME="spark-mvp"

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "[kind] cluster already exists: ${CLUSTER_NAME}"
  kubectl cluster-info
  exit 0
fi

CFG="$(mktemp)"
trap 'rm -f "${CFG}"' EXIT

cat <<'YAML' > "${CFG}"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: 80
        listenAddress: "0.0.0.0"
        protocol: TCP
      - containerPort: 30443
        hostPort: 443
        listenAddress: "0.0.0.0"
        protocol: TCP
YAML

kind create cluster --name "${CLUSTER_NAME}" --config "${CFG}"
kubectl cluster-info
echo "[kind] ready: ${CLUSTER_NAME}"

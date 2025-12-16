#!/usr/bin/env bash
set -euo pipefail
CLUSTER_NAME="spark-mvp"
kind delete cluster --name "${CLUSTER_NAME}" || true
echo "[kind] removed: ${CLUSTER_NAME}"

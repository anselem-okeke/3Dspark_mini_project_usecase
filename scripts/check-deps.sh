#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }

# cluster/runtime
need docker
need kind

# k8s tooling
need kubectl
need helm

# templating/utils most scripts rely on it
need envsubst
need sed
need curl
need jq

echo "[deps] all required tools are installed"

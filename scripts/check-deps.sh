#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "[deps] Missing dependency: $1"; exit 1; }; }

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

# 1) Docker must support --format (kind relies on it)
if ! docker ps --format '{{.ID}}' >/dev/null 2>&1; then
  echo "[deps] ERROR: your docker CLI does not support --format (kind requires modern docker-ce)."
  echo "[deps] Fix: run: make deps-ubuntu"
  exit 1
fi

# 2) Docker daemon must be reachable as current user (no sudo)
if ! docker info >/dev/null 2>&1; then
  echo "[deps] ERROR: cannot talk to Docker daemon as current user."
  echo "[deps] Fix: run: sudo usermod -aG docker $USER && newgrp docker"
  echo "[deps] (or log out/in) then re-run: make up"
  exit 1
fi

echo "[deps] all required tools are installed"


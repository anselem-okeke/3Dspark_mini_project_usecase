#!/usr/bin/env bash
set -euo pipefail

fail() { echo "[deps] ERROR: $*" >&2; exit 1; }
ok()   { echo "[deps] $*"; }

need() { command -v "$1" >/dev/null 2>&1 || fail "missing '$1'"; }

need bash
need curl
need jq
need envsubst
need sed
need docker
need kubectl
need helm
need kind

# Docker must support --format (kind requires it)
if ! docker ps --format '{{.ID}}' >/dev/null 2>&1; then
  fail "your docker CLI does not support --format (kind requires modern docker-ce / docker.io). Run: make deps-ubuntu"
fi

# Docker daemon must be reachable
if ! docker info >/dev/null 2>&1; then
  fail "docker daemon not reachable. If you just installed docker: 'sudo usermod -aG docker $USER' then re-login (or 'newgrp docker')."
fi

ok "all required tools are installed and docker is compatible with kind"


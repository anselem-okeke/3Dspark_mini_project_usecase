#!/usr/bin/env bash
set -euo pipefail

# Installs missing deps for this repo on Ubuntu/Debian.
# - apt: curl, jq, gettext-base (envsubst), docker.io
# - binaries: kubectl, helm, kind (more reliable than apt repos)

log() { echo "[deps] $*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  if need_cmd sudo; then
    SUDO="sudo"
  else
    echo "ERROR: not root and sudo is not installed. Run as root or install sudo."
    exit 1
  fi
fi

if ! need_cmd apt-get; then
  echo "ERROR: apt-get not found. This script supports Ubuntu/Debian."
  exit 1
fi

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  armv7l|armv7) ARCH="arm" ;;
  *)
    echo "ERROR: unsupported arch: $(uname -m)"
    exit 1
    ;;
esac

install_apt_pkgs() {
  local pkgs=("$@")
  log "apt update + install: ${pkgs[*]}"
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y --no-install-recommends "${pkgs[@]}"
}

# --- base deps (always safe) ---
BASE_PKGS=(curl ca-certificates jq gettext-base)
MISSING_BASE=()
for p in "${BASE_PKGS[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING_BASE+=("$p")
done
if ((${#MISSING_BASE[@]} > 0)); then
  install_apt_pkgs "${MISSING_BASE[@]}"
else
  log "base packages already installed"
fi

# sed is part of base OS; envsubst comes from gettext-base
if ! need_cmd envsubst; then
  log "envsubst missing -> installing gettext-base"
  install_apt_pkgs gettext-base
fi

# --- docker (apt) ---
if ! need_cmd docker; then
  log "docker missing -> installing docker.io"
  install_apt_pkgs docker.io
  ${SUDO} systemctl enable --now docker || true
else
  log "docker already installed"
fi

# allow current user to run docker without sudo
if need_cmd docker && [[ "${EUID}" -ne 0 ]]; then
  if ! groups | grep -q '\bdocker\b'; then
    log "adding ${USER} to docker group (re-login required)"
    ${SUDO} usermod -aG docker "${USER}" || true
    log "IMPORTANT: log out/in (or 'newgrp docker') so 'docker ps' works without sudo"
  fi
fi

# --- kubectl (binary) ---
if ! need_cmd kubectl; then
  log "kubectl missing -> installing latest stable"
  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl"
  chmod +x /tmp/kubectl
  ${SUDO} mv /tmp/kubectl /usr/local/bin/kubectl
else
  log "kubectl already installed"
fi

# --- helm (binary via official script) ---
if ! need_cmd helm; then
  log "helm missing -> installing (get-helm-3)"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | ${SUDO} bash
else
  log "helm already installed"
fi

# --- kind (binary) ---
if ! need_cmd kind; then
  log "kind missing -> installing latest release"
  KIND_VERSION="${KIND_VERSION:-}"
  if [[ -z "${KIND_VERSION}" ]]; then
    KIND_VERSION="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r .tag_name)"
  fi
  curl -fsSLo /tmp/kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${ARCH}"
  chmod +x /tmp/kind
  ${SUDO} mv /tmp/kind /usr/local/bin/kind
else
  log "kind already installed"
fi

log "done"
log "versions:"
docker --version || true
kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null || true
helm version --short 2>/dev/null || true
kind --version || true
envsubst --version 2>/dev/null || true
jq --version || true

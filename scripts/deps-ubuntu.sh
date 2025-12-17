#!/usr/bin/env bash
set -euo pipefail

log() { echo "[deps] $*"; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  need_cmd sudo || { echo "ERROR: not root and sudo missing"; exit 1; }
  SUDO="sudo"
fi

need_cmd apt-get || { echo "ERROR: apt-get not found (Ubuntu/Debian only)"; exit 1; }

# --- sanity: refuse EOL distros like trusty ---
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  log "Detected OS: ${PRETTY_NAME:-unknown}"
  # Trusty is 14.04; it will break modern docker/kind installs.
  if [[ "${VERSION_CODENAME:-}" == "trusty" ]]; then
    echo "ERROR: Ubuntu trusty is EOL and will not work reliably with modern Docker/kind."
    echo "Fix: update your Vagrant box to ubuntu/jammy64 (22.04) and recreate the VM."
    exit 1
  fi
fi

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "ERROR: unsupported arch: $(uname -m)"
    exit 1
    ;;
esac

install_apt() {
  log "apt update + install: $*"
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y --no-install-recommends "$@"
}

# base tools
install_apt curl ca-certificates jq gettext-base sed gnupg lsb-release

# --- Docker CE (modern CLI required by kind) ---
if ! need_cmd docker || ! docker ps --format '{{.ID}}' >/dev/null 2>&1; then
  log "Installing modern Docker (docker-ce)..."
  ${SUDO} install -m 0755 -d /etc/apt/keyrings

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg

  UBUNTU_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    ${UBUNTU_CODENAME} stable" | ${SUDO} tee /etc/apt/sources.list.d/docker.list > /dev/null

  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  ${SUDO} systemctl enable --now docker || true
else
  log "docker already installed and supports --format"
fi

# docker group for non-root usage
if [[ "${EUID}" -ne 0 ]]; then
  if ! groups | grep -q '\bdocker\b'; then
    log "Adding ${USER} to docker group (re-login required)"
    ${SUDO} usermod -aG docker "${USER}" || true
    log "Run: newgrp docker  (or log out/in) before running make up"
  fi
fi

# --- kubectl (binary) ---
if ! need_cmd kubectl; then
  log "Installing kubectl stable..."
  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl"
  chmod +x /tmp/kubectl
  ${SUDO} mv /tmp/kubectl /usr/local/bin/kubectl
else
  log "kubectl already installed"
fi

# --- helm ---
if ! need_cmd helm; then
  log "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | ${SUDO} bash
else
  log "helm already installed"
fi

# --- kind (no GitHub API; uses releases/latest redirect) ---
if ! need_cmd kind; then
  log "Installing kind..."
  KIND_URL="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/kubernetes-sigs/kind/releases/latest)"
  KIND_TAG="${KIND_URL##*/}"  # e.g. v0.30.0
  curl -fsSLo /tmp/kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_TAG}/kind-linux-${ARCH}"
  chmod +x /tmp/kind
  ${SUDO} mv /tmp/kind /usr/local/bin/kind
else
  log "kind already installed"
fi

log "done. versions:"
docker --version || true
kubectl version --client --short 2>/dev/null || true
helm version --short 2>/dev/null || true
kind --version || true
envsubst --version 2>/dev/null || true
jq --version || true
#!/usr/bin/env bash
set -euo pipefail

# Installs missing deps for this repo on Ubuntu/Debian.
# - apt: curl, jq, gettext-base (envsubst), ca-certificates, gnupg, lsb-release
# - docker: docker-ce (official repo) + docker-buildx-plugin + docker-compose-plugin
# - binaries: kubectl, helm, kind

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

ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  armv7l|armv7) ARCH="armhf" ;;
  *)
    echo "ERROR: unsupported arch: ${ARCH_RAW}"
    exit 1
    ;;
esac

install_apt_pkgs() {
  local pkgs=("$@")
  log "apt update + install: ${pkgs[*]}"
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y --no-install-recommends "${pkgs[@]}"
}

# --- base deps ---
BASE_PKGS=(curl ca-certificates jq gettext-base gnupg lsb-release)
MISSING_BASE=()
for p in "${BASE_PKGS[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING_BASE+=("$p")
done
if ((${#MISSING_BASE[@]} > 0)); then
  install_apt_pkgs "${MISSING_BASE[@]}"
else
  log "base packages already installed"
fi

# envsubst comes from gettext-base
if ! need_cmd envsubst; then
  log "envsubst missing -> installing gettext-base"
  install_apt_pkgs gettext-base
fi

# --- Docker CE (official repo) ---
install_docker_ce() {
  log "installing/upgrading Docker CE (official repo)"

  # Remove common conflicting packages (safe if not installed)
  ${SUDO} apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc >/dev/null 2>&1 || true

  # Keyrings dir
  ${SUDO} install -m 0755 -d /etc/apt/keyrings

  # Detect distro
  . /etc/os-release
  DISTRO_ID="${ID}"
  CODENAME="${VERSION_CODENAME:-}"
  if [[ -z "${CODENAME}" ]] && need_cmd lsb_release; then
    CODENAME="$(lsb_release -cs)"
  fi
  if [[ -z "${CODENAME}" ]]; then
    echo "ERROR: could not determine distro codename (VERSION_CODENAME/lsb_release)."
    exit 1
  fi

  # Docker supports ubuntu/debian in download.docker.com paths
  case "${DISTRO_ID}" in
    ubuntu|debian) ;;
    *)
      echo "ERROR: unsupported distro for this installer: ${DISTRO_ID} (expected ubuntu/debian)"
      exit 1
      ;;
  esac

  # Add Docker’s official GPG key
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  # Add repo
  REPO_FILE="/etc/apt/sources.list.d/docker.list"
  echo \
"deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO_ID} ${CODENAME} stable" \
  | ${SUDO} tee "${REPO_FILE}" >/dev/null

  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  ${SUDO} systemctl enable --now docker || true
}

# If docker missing, install it. If docker exists but doesn't support --format, upgrade to docker-ce.
if ! need_cmd docker; then
  log "docker missing -> installing Docker CE"
  install_docker_ce
else
  log "docker already installed -> checking --format support"
  if ! docker ps --format '{{.ID}}' >/dev/null 2>&1; then
    log "docker exists but --format is not supported -> upgrading to Docker CE"
    install_docker_ce
  else
    log "docker supports --format (ok)"
  fi
fi

# allow current user to run docker without sudo
if need_cmd docker && [[ "${EUID}" -ne 0 ]]; then
  if ! groups | grep -q '\bdocker\b'; then
    log "adding ${USER} to docker group (re-login required)"
    ${SUDO} usermod -aG docker "${USER}" || true
    log "IMPORTANT: log out/in (or run: newgrp docker) so 'docker ps' works without sudo"
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
  curl -fsSLo /tmp/kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${ARCH_RAW}"
  chmod +x /tmp/kind
  ${SUDO} mv /tmp/kind /usr/local/bin/kind
else
  log "kind already installed"
fi

# --- final hard check: docker must support --format ---
if ! docker ps --format '{{.ID}}' >/dev/null 2>&1; then
  echo "[deps] ERROR: docker CLI still does not support --format. kind will fail."
  echo "[deps] Please paste: docker --version && which docker && docker ps --help | head -n 30"
  exit 1
fi

log "done"
log "versions:"
docker --version || true
kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null || true
helm version --short 2>/dev/null || true
kind --version || true
envsubst --version 2>/dev/null || true
jq --version || true


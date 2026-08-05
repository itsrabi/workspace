#!/usr/bin/env bash
set -euo pipefail

if command -v podman >/dev/null 2>&1; then
  echo "Podman already installed: $(command -v podman)"
  exit 0
fi

if [[ "${1:-}" == "--dry-run" ]]; then
  echo "[dry-run] Would attempt Podman installation"
  exit 0
fi

# Detect OS.
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
fi

need_sudo=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    need_sudo="sudo"
  else
    echo "Podman is not installed and sudo is not available. Install Podman manually." >&2
    exit 1
  fi
fi

install_with_apt() {
  ${need_sudo} apt-get update -y
  ${need_sudo} apt-get install -y podman
}

install_with_dnf() {
  ${need_sudo} dnf install -y podman
}

install_with_yum() {
  ${need_sudo} yum install -y podman
}

if [[ "${ID:-}" == "fedora" || "${ID_LIKE:-}" == *"fedora"* || "${ID:-}" == "rhel" || "${ID_LIKE:-}" == *"rhel"* ]]; then
  if command -v dnf >/dev/null 2>&1; then
    install_with_dnf
  else
    install_with_yum
  fi
elif [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *"debian"* ]]; then
  install_with_apt
elif command -v brew >/dev/null 2>&1; then
  # macOS
  brew install podman
else
  echo "Unsupported OS for automatic Podman install. Please install Podman manually." >&2
  echo "Podman: https://podman.io/getting-started/installation" >&2
  exit 1
fi

# Final check
if command -v podman >/dev/null 2>&1; then
  echo "Podman installation complete: $(command -v podman)"
  exit 0
fi

echo "Podman installation attempted but podman still not found. Install manually." >&2
exit 1

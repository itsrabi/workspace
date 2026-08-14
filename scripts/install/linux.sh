#!/usr/bin/env bash
set -euo pipefail

repo_root="$(realpath "$(dirname "$0")/../..")"

need_sudo=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    need_sudo="sudo"
  else
    echo "This installer requires root privileges via sudo on Fedora-family Linux." >&2
    exit 1
  fi
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Unsupported distribution: missing /etc/os-release. Fedora-family Linux is required." >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release

if [[ "${ID:-}" != "fedora" && " ${ID_LIKE:-} " != *" fedora "* && "${ID:-}" != "rhel" && " ${ID_LIKE:-} " != *" rhel "* ]]; then
  echo "Unsupported distribution: Fedora-family Linux is required." >&2
  exit 1
fi

dnf_cmd="dnf"
if ! command -v "$dnf_cmd" >/dev/null 2>&1; then
  echo "Unsupported distribution: dnf is required for Fedora-family installation." >&2
  exit 1
fi

install_dnf_packages() {
  ${need_sudo} "$dnf_cmd" -y install --setopt=install_weak_deps=false \
    bash \
    ca-certificates \
    curl \
    diffutils \
    git \
    gzip \
    make \
    tar \
    unzip \
    xz \
    nodejs \
    npm \
    tree \
    tmux \
    which \
    xclip \
    wl-clipboard \
    procps-ng \
    util-linux \
    rsync \
    iproute \
    sudo \
    shadow-utils \
    ripgrep \
    fzf \
    bat \
    fd-find \
    gcc \
    gcc-c++ \
    cmake \
    pkgconf-pkg-config \
    poetry \
    uv \
    python3 \
    python3-pip
  ${need_sudo} "$dnf_cmd" clean all
}

enable_yazi_repo() {
  ${need_sudo} "$dnf_cmd" -y install dnf-plugins-core
  ${need_sudo} "$dnf_cmd" -y copr enable lihaohong/yazi
  ${need_sudo} "$dnf_cmd" -y install yazi
  ${need_sudo} "$dnf_cmd" clean all
}

install_neovim() {
  if command -v nvim >/dev/null 2>&1 && nvim --version | grep '^NVIM v0.12.4$' >/dev/null 2>&1; then
    return 0
  fi

  archive_name="nvim-linux-x86_64.tar.gz"
  archive_path="/tmp/${archive_name}"
  curl -fsSL "https://github.com/neovim/neovim/releases/download/v0.12.4/${archive_name}" -o "$archive_path"
  ${need_sudo} rm -rf /opt/nvim-linux-x86_64
  ${need_sudo} tar -C /opt -xzf "$archive_path"
  ${need_sudo} ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
  rm -f "$archive_path"
  nvim --version | grep '^NVIM v0.12.4$' >/dev/null
}

install_pi() {
  ${need_sudo} npm install -g --ignore-scripts @earendil-works/pi-coding-agent
  command -v pi >/dev/null 2>&1
  PI_SKIP_VERSION_CHECK=1 PI_TELEMETRY=0 pi install npm:pi-web-access
  PI_SKIP_VERSION_CHECK=1 PI_TELEMETRY=0 pi install npm:@quintinshaw/pi-dynamic-workflows
  PI_SKIP_VERSION_CHECK=1 PI_TELEMETRY=0 pi install npm:@narumitw/pi-plan-mode
}

install_dnf_packages
enable_yazi_repo
install_neovim
install_pi
bash "$repo_root/scripts/install/link-dotfiles.sh" --repo-root "$repo_root" --home "$HOME"

# syntax=docker/dockerfile:1.6

# Fedora minimal-ish base. We keep the image lean but include common engineering tools.
FROM fedora:44

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=1000

# Placeholder for your personal dotfiles repo that contains Neovim config.
#
# IMPORTANT: leave DOTFILES_REPO empty to build with the repo-owned Neovim config.
# External override lookup order inside the cloned repo:
#   1) .config/nvim
#   2) nvim
ARG DOTFILES_REPO=""                # e.g. https://github.com/<you>/dotfiles.git
ARG DOTFILES_REV="master"          # e.g. master/main

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    SHELL=/bin/bash

# Base packages.
# Notes:
# - fd-find package provides the `fd` binary.
# - Neovim is installed from a pinned upstream release tarball below.
RUN set -euxo pipefail; \
    dnf -y update; \
    dnf -y install --setopt=install_weak_deps=false \
      bash \
      ca-certificates \
      curl \
      git \
      gzip \
      make \
      tar \
      unzip \
      xz \
      tree \
      which \
      procps-ng \
      util-linux \
      sudo \
      shadow-utils \
      podman \
      # Editors / CLI tools \
      ripgrep \
      fzf \
      bat \
      fd-find \
      # Common dev toolchains \
      gcc \
      gcc-c++ \
      cmake \
      pkgconf-pkg-config \
      # Often-needed interpreters \
      python3 \
      python3-pip; \
    dnf clean all; \
    rm -rf /var/cache/dnf

RUN set -euxo pipefail; \
    sudo dnf -y install dnf-plugins-core; \
    sudo dnf -y copr enable lihaohong/yazi; \
    sudo dnf -y install yazi; \
    sudo dnf clean all; \
    rm -rf /var/cache/dnf

# Install pinned Neovim so vim.pack is available.
RUN set -euxo pipefail; \
    curl -fsSL "https://github.com/neovim/neovim/releases/download/v0.12.4/nvim-linux-x86_64.tar.gz" -o /tmp/nvim-linux-x86_64.tar.gz; \
    tar -C /opt -xzf /tmp/nvim-linux-x86_64.tar.gz; \
    ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim; \
    rm -f /tmp/nvim-linux-x86_64.tar.gz; \
    nvim --version | grep '^NVIM v0.12.4$'
# Locale setup (Fedora base images don't always include it).
# We keep it robust with a best-effort approach.
RUN set -euxo pipefail; \
    (dnf -y install --setopt=install_weak_deps=false glibc-langpack-en || true); \
    localedef -i en_US -f UTF-8 en_US.UTF-8 || true

# Create non-root user.
RUN set -euxo pipefail; \
    groupadd --gid "$USER_GID" "$USERNAME"; \
    useradd  --uid "$USER_UID" --gid "$USER_GID" -m "$USERNAME" -s /bin/bash; \
    usermod -aG wheel "$USERNAME"; \
    echo "%wheel ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-wheel-nopasswd; \
    chmod 0440 /etc/sudoers.d/99-wheel-nopasswd

COPY scripts/dev-image-statusline-bash-prompt-block /etc/dev-image-statusline-bash-prompt-block

RUN set -euxo pipefail; \
    mkdir -p /etc; \
    # Install statusline snippet globally so it is repeatable regardless of host/user dotfiles.
    # Fedora interactive bash shells source /etc/bashrc, and ~/.bashrc typically sources it as well.
    if ! grep -q 'dev-image-statusline-bash-prompt' /etc/bashrc; then \
      echo '' >> /etc/bashrc; \
      echo '# dev-image-statusline-bash-prompt' >> /etc/bashrc; \
      echo '[ -f /etc/dev-image-statusline-bash-prompt-block ] && . /etc/dev-image-statusline-bash-prompt-block' >> /etc/bashrc; \
    fi
 
# Repo-owned Neovim configuration (default).
# Stored once under /etc/xdg so both root and the non-root user share it.
COPY configs/nvim/ /etc/xdg/nvim/

RUN set -euxo pipefail; \
  mkdir -p "/home/${USERNAME}/.config" /root/.config; \
  ln -sfn "/etc/xdg/nvim" "/home/${USERNAME}/.config/nvim"; \
  ln -sfn "/etc/xdg/nvim" "/root/.config/nvim"; \
  chown -R "${USERNAME}:${USER_GID}" /etc/xdg/nvim; \
  if [ ! -f "/etc/xdg/nvim/init.lua" ]; then \
    echo "[error] Repo-owned Neovim config missing: /etc/xdg/nvim/init.lua"; \
    exit 1; \
  fi

# Optional override Neovim config from an external dotfiles repo.
RUN set -euxo pipefail; \
  if [ -n "${DOTFILES_REPO}" ]; then \
    echo "Importing Neovim config from ${DOTFILES_REPO}@${DOTFILES_REV}"; \
    rm -rf /tmp/dotfiles; \
    git clone --depth 1 --branch "${DOTFILES_REV}" "${DOTFILES_REPO}" /tmp/dotfiles; \
    NVIM_SRC=""; \
    if [ -d "/tmp/dotfiles/.config/nvim" ]; then \
      NVIM_SRC="/tmp/dotfiles/.config/nvim"; \
    elif [ -d "/tmp/dotfiles/nvim" ]; then \
      NVIM_SRC="/tmp/dotfiles/nvim"; \
    fi; \
    if [ -z "$NVIM_SRC" ]; then \
      echo "[error] DOTFILES_REPO was provided, but no Neovim config was found in the cloned repo."; \
      echo "[error] Looked for: /tmp/dotfiles/.config/nvim and /tmp/dotfiles/nvim"; \
      exit 1; \
    fi; \
    rm -rf "/home/${USERNAME}/.config/nvim"/*; \
    cp -a "$NVIM_SRC"/* "/home/${USERNAME}/.config/nvim/"; \
    rm -rf /tmp/dotfiles; \
  else \
    echo "DOTFILES_REPO is empty; using repo-owned Neovim config"; \
  fi

# Workspace directory convention for devcontainers.
RUN set -euxo pipefail; \
    mkdir -p /workspaces; \
    chown -R "${USERNAME}:${USER_GID}" /home/${USERNAME} /workspaces

COPY scripts/sandbox /usr/local/bin/sandbox
RUN set -euxo pipefail; \
    chmod +x /usr/local/bin/sandbox; \
    chown "${USERNAME}:${USER_GID}" /usr/local/bin/sandbox
USER ${USERNAME}
WORKDIR /workspaces

# Quick sanity for image users.
# (nvim is headless; `+q` exits immediately.)
RUN nvim --headless "+q" || true

# syntax=docker/dockerfile:1.6

# Fedora minimal-ish base. We keep the image lean but include common engineering tools.
FROM fedora:40

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=1000

# Placeholder for your personal dotfiles repo that contains Neovim config.
#
# Expected layout options (choose what matches your repo):
#   - <repo>/.config/nvim
#   - <repo>/nvim
#   - <repo>/<DOTFILES_NVIM_PATH>  (custom)
#
# IMPORTANT: leave DOTFILES_REPO empty to build without importing your config yet.
ARG DOTFILES_REPO=""                # e.g. https://github.com/<you>/dotfiles.git
ARG DOTFILES_REV="master"          # e.g. master/main
ARG DOTFILES_NVIM_PATH=""         # e.g. .config/nvim (optional override)
ARG REQUIRE_DOTFILES_CONFIG="false"

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    SHELL=/bin/bash

# Base packages.
# Notes:
# - fd-find package provides the `fd` binary.
# - neovim provides `nvim`.
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
      which \
      procps-ng \
      util-linux \
      sudo \
      shadow-utils \
      # Editors / CLI tools \
      neovim \
      ripgrep \
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
 
 # Default Neovim config (so `nvim --headless` works even before dotfiles are wired).
 # This will be overwritten if DOTFILES_REPO is provided.
RUN set -euxo pipefail; \
    mkdir -p /home/${USERNAME}/.config/nvim; \
    cat > /home/${USERNAME}/.config/nvim/init.vim <<'EOF'
" Minimal safe default. Replace/import via DOTFILES_REPO build args.
set nocompatible
syntax on
filetype plugin indent on
EOF

# Import Neovim config from your dotfiles repo.
# This is designed to be easy to fill in later (no hard dependency during build).
RUN --mount=type=cache,target=/var/cache/dnf \
    set -euxo pipefail; \
    if [ -n "${DOTFILES_REPO}" ]; then \
      echo "Importing Neovim config from ${DOTFILES_REPO}@${DOTFILES_REV}"; \
      dnf -y install --setopt=install_weak_deps=false git; \
      rm -rf /tmp/dotfiles; \
      git clone --depth 1 --branch "${DOTFILES_REV}" "${DOTFILES_REPO}" /tmp/dotfiles; \
      mkdir -p "/home/${USERNAME}/.config/nvim"; \
      NVIM_SRC=""; \
      if [ -n "${DOTFILES_NVIM_PATH}" ] && [ -d "/tmp/dotfiles/${DOTFILES_NVIM_PATH}" ]; then \
        NVIM_SRC="/tmp/dotfiles/${DOTFILES_NVIM_PATH}"; \
      elif [ -d "/tmp/dotfiles/.config/nvim" ]; then \
        NVIM_SRC="/tmp/dotfiles/.config/nvim"; \
      elif [ -d "/tmp/dotfiles/nvim" ]; then \
        NVIM_SRC="/tmp/dotfiles/nvim"; \
      fi; \
      if [ -z "$NVIM_SRC" ]; then \
        echo "[warn] Could not find Neovim config in dotfiles."; \
        echo "[warn] Tried DOTFILES_NVIM_PATH='${DOTFILES_NVIM_PATH}', .config/nvim, and nvim/."; \
        if [ "${REQUIRE_DOTFILES_CONFIG}" = "true" ]; then exit 1; else true; fi; \
      else \
        rm -rf "/home/${USERNAME}/.config/nvim"/*; \
        cp -a "$NVIM_SRC"/* "/home/${USERNAME}/.config/nvim/"; \
      fi; \
      rm -rf /tmp/dotfiles; \
    else \
      echo "DOTFILES_REPO is empty; skipping Neovim dotfiles import"; \
    fi

# Workspace directory convention for devcontainers.
RUN set -euxo pipefail; \
    mkdir -p /workspaces; \
    chown -R "${USERNAME}:${USER_GID}" /home/${USERNAME} /workspaces

COPY scripts/smoke-check.sh /workspaces/smoke-check.sh
RUN set -euxo pipefail; \
    chmod +x /workspaces/smoke-check.sh; \
    chown "${USERNAME}:${USER_GID}" /workspaces/smoke-check.sh
USER ${USERNAME}
WORKDIR /workspaces

# Quick sanity for image users.
# (nvim is headless; `+q` exits immediately.)
RUN nvim --headless "+q" || true

# Fedora Dev Container Base (Podman + Neovim)

This repo builds a **Fedora-based devcontainer base image** meant to be extended per-project.

It installs (base image):
- `nvim` (Neovim)
- `rg` (ripgrep)
- `fd` (`fd-find`)
- Plus common software-engineering utilities (see **Installed packages (base image)** section).

## What you get
- A `Dockerfile` that produces the base image.
- A Dev Containers config stub at `.devcontainer/devcontainer.json` (optional for VS Code).
- A GitHub Actions workflow to build/push to Azure Container Registry (ACR): `.github/workflows/build-and-push-acr.yml`.
- A local developer workflow via `make` (`install`, `smoke`, `workspace`, `sandbox`).

## Quickstart (recommended)
### 1) Create the image
Your first step is `make install`.

`make install` builds the image from the `Dockerfile` as `devcontainer-base-fedora:local`.

```bash
make install
```

### 2) Enter a disposable container
```bash
make run
```

### 3) Smoke-test the image (optional)
```bash
make smoke
```

`make smoke` runs `scripts/smoke-check.sh` via a bind mount.

### 4) Create the long-lived workspace container
```bash
make workspace
```

`make workspace` retags the base image and creates/runs the long-lived `fedora-workspace` container.

### 5) Sandbox the current directory
```bash
make sandbox
```

`make sandbox` is a host convenience wrapper around the in-container `sandbox run` flow.

## In-container sandbox rule
Inside `fedora-workspace`, `sandbox create` / `sandbox run` must be launched from a **host-mounted** path under:
- `/mnt/<drive>/...`

This matches the repo's `scripts/sandbox` behavior: the host Podman daemon is responsible for creating the bind mount, so container-only paths (for example `/workspaces/...` inside the container) are not sufficient.

## Neovim configuration (repo-owned default)
By default, the image ships a canonical Neovim config from this repository at:
- `configs/nvim/`

Default layout:
- `configs/nvim/init.lua` (thin entrypoint; sets leaders, then `require("config")`)
- `configs/nvim/lua/config/*` (core modules)
- `configs/nvim/lua/plugins/*` (category spec files aggregated by `configs/nvim/lua/config/pack.lua`)
- `configs/nvim/lua/utils/*`
- `configs/nvim/lua/lsp/*`
- `configs/nvim/after/ftplugin/*`

The repo-owned default uses Neovim's built-in `vim.pack` (not a third-party plugin manager).

### Build-time override via your dotfiles
You may override the default Neovim config at build time using only:
- `DOTFILES_REPO`
- `DOTFILES_REV`

Example:
```bash
make build \
  DOTFILES_REPO="https://github.com/<you>/dotfiles.git" \
  DOTFILES_REV="master"
```

Only `DOTFILES_REPO` and `DOTFILES_REV` are supported for build-time Neovim overrides.
## Container image name
Local image tag:
- `devcontainer-base-fedora:local`

(Override via `make IMAGE=...`.)

## ACR CI/CD
See `.github/workflows/build-and-push-acr.yml`.

It expects placeholder secrets such as:
- `ACR_LOGIN_SERVER`
- `ACR_USERNAME`
- `ACR_PASSWORD`

Optional dotfiles override secrets:
- `DOTFILES_REPO`
- `DOTFILES_REV` (defaults to `master`)

## Notes
- The container runs as the non-root user `developer`.
- The working directory inside the container is `/workspaces`.

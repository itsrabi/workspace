# Fedora Dev Container Base (Podman + Neovim)

This repo builds a **Fedora-based devcontainer base image** meant to be extended per-project.

It installs (base image):
- `nvim` (Neovim)
- `rg` (ripgrep)
- `fd` (`fd-find`)
- Plus common software-engineering utilities (see **Installed packages** section).

## What you get
- A `Dockerfile` that produces the base image.
- A Dev Containers config stub at `.devcontainer/devcontainer.json` (optional for VS Code).
- A GitHub Actions workflow to build/push to Azure Container Registry (ACR): `.github/workflows/build-and-push-acr.yml`.
- A local developer workflow via `make`.

## Quickstart (recommended)
### 1) Create the image
Your first step is `make install`.

`make install` will:
1) Ensure **Podman** is installed (tries automatically on Windows/macOS/Linux).
2) Build the image from the `Dockerfile`.

```bash
make install
```

### 2) Enter the container
```bash
make run
```

### 3) Smoke-test the image (optional)
```bash
make smoke
```

## Installed packages (base image)
The Dockerfile installs these tools:
- Shell/ops: `bash`, `sudo`, `ca-certificates`, `curl`, `procps-ng`, `util-linux`
- Build basics: `make`, `gcc`, `gcc-c++`, `cmake`, `pkgconf-pkg-config`
- Packaging helpers: `tar`, `gzip`, `unzip`, `xz`, `which`
- VCS/network: `git`
- Editors/search: `neovim`, `ripgrep`, `fd-find` (provides `fd`)
- Language tooling: `python3`, `python3-pip`
- Locale best-effort: `glibc-langpack-en` + `localedef` (best-effort)

## Neovim configuration source (your dotfiles)
By default, the image ships with a minimal `~/.config/nvim/init.vim`.

When you’re ready, you can import your Neovim config at **build time** by passing build args:
- `DOTFILES_REPO` (e.g. `https://github.com/<you>/dotfiles.git`) — leave empty to skip
- `DOTFILES_REV` (branch/tag name)
- `DOTFILES_NVIM_PATH` (optional override of where Neovim config lives inside the dotfiles repo)
- `REQUIRE_DOTFILES_CONFIG` (`true`/`false`): fail build if the config cannot be found

Example:
```bash
make build \
  DOTFILES_REPO="https://github.com/<you>/dotfiles.git" \
  DOTFILES_REV="main" \
  DOTFILES_NVIM_PATH=".config/nvim" \
  REQUIRE_DOTFILES_CONFIG=true
```

Expected (common) dotfiles layouts the Dockerfile attempts automatically when `DOTFILES_NVIM_PATH` is not set:
- `.config/nvim`
- `nvim/`

## Container image name
Local image tag:
- `devcontainer-base-fedora:local`

(Override via `make IMAGE=...`.)

## ACR CI/CD
See `.github/workflows/build-and-push-acr.yml`. It expects placeholder secrets such as:
- `ACR_LOGIN_SERVER`
- `ACR_USERNAME`
- `ACR_PASSWORD`

## Notes
- The container runs as the non-root user `developer`.
- The working directory inside the container is `/workspaces`.

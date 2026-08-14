# Fedora Dev Container Base (Podman + Neovim)

This repo builds a **Fedora-based devcontainer base image** intended to be extended per-project.

Key architecture (per `AGENTS.md`):
- **Repo-owned dotfiles** live in `dotfiles/` and are installed by `scripts/install/link-dotfiles.sh`.
- **Container definition** lives in `container/Containerfile` (with VS Code config in `container/devcontainer.json`).
- **Container/local workflows** live in `scripts/container/*`.
- **User-facing workflows** live in `Makefile`.

## What you get
 - A `container/Containerfile` image that installs:
   - Neovim (`v0.12.4`)
   - `rg`, `fd-find`, `fzf`, `yazi`
   - common tooling (see the Containerfile + smoke script)
   - Pi agent + required Pi packages

## Supported workflows

### Native (Fedora-family Linux)
1) Bootstrap host tooling and link dotfiles:
```bash
make install
```

### Container workflows (host + Podman)
All container workflows are based on the local image tag:
- **Local image:** `workspace:local`
- **Workspace container name:** `workspace`

Build + smoke:
```bash
make container-build
make container-smoke
```

Start + use:
```bash
make container-start
make container-shell
```

Lifecycle helpers:
```bash
make container-stop
make container-rm
make container-rebuild
```

Per-directory sandbox (end-user command):
```bash
make sandbox
```

### Push to ACR
```bash
make push
```
You must set:
- `ACR_LOGIN_SERVER`
- `ACR_USERNAME`
- `ACR_PASSWORD`

By default, it pushes to ACR repo `workspace` with tag `latest`.

## In-container sandbox rule
The `bin/sandbox` command creates/uses per-directory containers by bind-mounting a host-visible path.

- **Windows host:** run `make sandbox` (or the sandbox action) from the repo root.
  The in-container sandbox flow requires host-visible paths under `/mnt/<drive>/...`.
- **Linux host:** the workspace lifecycle mounts `$WORKSPACE_ROOT` into the workspace container at the same absolute path.
  `bin/sandbox` requires the current directory to be under that root.

## Neovim configuration (repo-owned default)
Neovim source of truth is:
- `dotfiles/.config/nvim/`

Default layout:
- `dotfiles/.config/nvim/init.lua` (thin entrypoint; calls `require("main")`)
- `dotfiles/.config/nvim/lua/main/core/*`
- `dotfiles/.config/nvim/lua/main/plugins/*`
- `dotfiles/.config/nvim/after/ftplugin/*`

`dotfiles/.config/nvim` is installed into the image and linked into `$HOME/.config/nvim` as a symlink.

## Where the implementations live
- Dotfile linking: `scripts/install/link-dotfiles.sh`
- Native installer: `scripts/install/linux.sh`
- Container smoke validation: `scripts/container/smoke-check.sh`
- Workspace lifecycle:
  - Windows host: `scripts/container/workspace.ps1`
  - Linux host: `scripts/container/workspace.sh`
- In-image user/prompt behavior: `dotfiles/.bashrc`

## Notes
- Container smoke validates:
  - tool availability
  - Pi agent packages
  - symlinked dotfiles (`~/.config/nvim` and `~/.bashrc`)
  - `whoami` equals the host username passed as `EXPECTED_USER`.

> Demo change: README updated again to exercise the repository automation workflow.

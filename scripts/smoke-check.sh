#!/usr/bin/env bash
set -euo pipefail

echo "== Versions =="
command -v nvim rg fd
nvim --version | head -n 5
rg --version
fd --version

echo "== Neovim headless smoke =="
# Headless Neovim exits immediately.
nvim --headless "+q"

echo "OK"

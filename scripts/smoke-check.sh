#!/usr/bin/env bash
set -euo pipefail

echo "== Versions =="
command -v nvim rg fd fzf
nvim --version | head -n 5
rg --version
fzf --version

echo "== Neovim headless smoke =="

# Load the config and verify key plugin modules are importable.
# Harpoon is configured to avoid save-on-change during VimLeave in headless runs.
nvim --headless "+lua \
    assert(pcall(require, 'plenary.path'), 'missing plenary.path') \
    assert(pcall(require, 'harpoon'), 'missing harpoon') \
    assert(pcall(require, 'fzf-lua'), 'missing fzf-lua') \
    assert(pcall(require, 'nvim-web-devicons'), 'missing nvim-web-devicons') \
" "+q"

# Verify plugin directories exist after startup (i.e., installation succeeded).
DATA_OPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/core/opt"

test -d "${DATA_OPT_DIR}/plenary.nvim"
test -d "${DATA_OPT_DIR}/harpoon"
test -d "${DATA_OPT_DIR}/fzf-lua"
test -d "${DATA_OPT_DIR}/nvim-web-devicons"

echo "OK"

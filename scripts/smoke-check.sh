#!/usr/bin/env bash
set -euo pipefail

echo "== Versions =="
command -v nvim rg fd fzf yazi
nvim --version | head -n 5
rg --version
fd --version
fzf --version
yazi --version
echo "== Neovim headless smoke =="

# Load the config and verify key plugin modules are importable.
# Harpoon is configured to avoid save-on-change during VimLeave in headless runs.
nvim --headless "+lua assert(pcall(require, 'plenary.path'), 'missing plenary.path'); assert(pcall(require, 'harpoon'), 'missing harpoon'); assert(pcall(require, 'fzf-lua'), 'missing fzf-lua'); assert(pcall(require, 'nvim-web-devicons'), 'missing nvim-web-devicons'); assert(pcall(require, 'snacks'), 'missing snacks'); assert(pcall(require, 'alpha'), 'missing alpha'); assert(vim.fn.exists(':Alpha') == 2, 'missing :Alpha command'); assert(vim.g.colors_name ~= nil and vim.g.colors_name ~= '', 'colorscheme not set')" +q

# Verify plugin directories exist after startup (i.e., installation succeeded).
DATA_OPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/core/opt"

test -d "${DATA_OPT_DIR}/plenary.nvim"
test -d "${DATA_OPT_DIR}/harpoon"
test -d "${DATA_OPT_DIR}/fzf-lua"
test -d "${DATA_OPT_DIR}/nvim-web-devicons"
test -d "${DATA_OPT_DIR}/snacks.nvim"
test -d "${DATA_OPT_DIR}/alpha-nvim"

echo "OK"

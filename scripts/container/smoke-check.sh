#!/usr/bin/env bash
set -euo pipefail

echo "== Versions =="
command -v nvim rg fd fzf yazi node npm pi sandbox
nvim --version | sed -n '1,5p'
rg --version
fd --version
fzf --version
yazi --version
node --version
npm --version
pi --version

echo "== User and dotfiles =="
if [[ -n "${EXPECTED_USER:-}" ]]; then
  test "$(whoami)" = "$EXPECTED_USER"
fi
test -L "$HOME/.config/nvim"
test -L "$HOME/.bashrc"
test "$(realpath "$HOME/.config/nvim")" = "/opt/workspace/dotfiles/.config/nvim"
test "$(realpath "$HOME/.bashrc")" = "/opt/workspace/dotfiles/.bashrc"
test -L "$HOME/.pi"
test "$(realpath "$HOME/.pi")" = "/opt/workspace/dotfiles/.pi"
test -L "$HOME/.config/pi"
test "$(realpath "$HOME/.config/pi")" = "/opt/workspace/dotfiles/.config/pi"

echo "== Pi packages =="
PI_LIST_OUTPUT="$(pi list)"
printf '%s\n' "$PI_LIST_OUTPUT"
printf '%s\n' "$PI_LIST_OUTPUT" | grep -Fq "pi-web-access"
printf '%s\n' "$PI_LIST_OUTPUT" | grep -Fq "@quintinshaw/pi-dynamic-workflows"
printf '%s\n' "$PI_LIST_OUTPUT" | grep -Fq "@narumitw/pi-plan-mode"
printf '%s\n' "$PI_LIST_OUTPUT" | grep -Fq "pi-agent-browser-native"
printf '%s\n' "$PI_LIST_OUTPUT" | grep -Fq "pi-hashline-edit-pro"
printf '%s\n' "$PI_LIST_OUTPUT" | grep -Fq "effect"
printf '%s\n' "$PI_LIST_OUTPUT" | grep -Fq "typebox"
printf '%s\n' "$PI_LIST_OUTPUT" | grep -Fq "pi-subagents"
printf '%s\n' "$PI_LIST_OUTPUT" | grep -Fq "@juicesharp/rpiv-todo"

echo "== Neovim headless smoke =="
nvim --headless "+lua assert(pcall(require, 'plenary.path'), 'missing plenary.path'); assert(pcall(require, 'harpoon'), 'missing harpoon'); assert(pcall(require, 'fzf-lua'), 'missing fzf-lua'); assert(pcall(require, 'nvim-web-devicons'), 'missing nvim-web-devicons'); assert(pcall(require, 'snacks'), 'missing snacks'); assert(pcall(require, 'alpha'), 'missing alpha'); assert(vim.fn.exists(':Alpha') == 2, 'missing :Alpha command'); assert(vim.g.colors_name ~= nil and vim.g.colors_name ~= '', 'colorscheme not set')" +q

DATA_OPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/core/opt"
test -d "${DATA_OPT_DIR}/plenary.nvim"
test -d "${DATA_OPT_DIR}/harpoon"
test -d "${DATA_OPT_DIR}/fzf-lua"
test -d "${DATA_OPT_DIR}/nvim-web-devicons"
test -d "${DATA_OPT_DIR}/snacks.nvim"
test -d "${DATA_OPT_DIR}/alpha-nvim"

echo "OK"

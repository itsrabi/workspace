#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash scripts/install/link-dotfiles.sh --repo-root <repo-root> [--home <home-dir>]" >&2
}

repo_root=""
home_dir="${HOME:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      shift
      if [[ $# -eq 0 ]]; then
        usage
        exit 64
      fi
      repo_root="$1"
      ;;
    --home)
      shift
      if [[ $# -eq 0 ]]; then
        usage
        exit 64
      fi
      home_dir="$1"
      ;;
    *)
      usage
      exit 64
      ;;
  esac
  shift
done

if [[ -z "$repo_root" || -z "$home_dir" ]]; then
  usage
  exit 64
fi

repo_root="$(realpath "$repo_root")"
export HOME="$home_dir"

repo_bashrc="$repo_root/dotfiles/.bashrc"
repo_nvim="$repo_root/dotfiles/.config/nvim"
repo_tmux="$repo_root/dotfiles/.config/tmux"
xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

if [[ ! -f "$repo_bashrc" ]]; then
  echo "Missing repo dotfile: $repo_bashrc" >&2
  exit 1
fi

if [[ ! -d "$repo_nvim" ]]; then
  echo "Missing repo dotfile directory: $repo_nvim" >&2
  exit 1
fi

if [[ ! -d "$repo_tmux" ]]; then
  echo "Missing repo dotfile directory: $repo_tmux" >&2
  exit 1
fi

link_target() {
  local source_path="$1"
  local target_path="$2"
  local source_realpath
  local target_realpath

  source_realpath="$(realpath "$source_path")"

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    if [[ -L "$target_path" ]]; then
      target_realpath="$(realpath "$target_path" 2>/dev/null || true)"
      if [[ "$target_realpath" == "$source_realpath" ]]; then
        return 0
      fi
    fi

    printf '%s\n' "$target_path" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$target_path")"
  ln -s "$source_realpath" "$target_path"
}

link_target "$repo_nvim" "$xdg_config_home/nvim"
link_target "$repo_tmux" "$xdg_config_home/tmux"
link_target "$repo_bashrc" "$HOME/.bashrc"


# If the caller provided a staging HOME/XDG_CONFIG_HOME inside this repo,
# ensure it does not persist as untracked working-tree state.
cleanup_staging=false

should_cleanup_staging_path() {
  local p="$1"

  # Relative paths are treated as repo-local staging.
  if [[ "$p" != /* && ! "$p" =~ ^[A-Za-z]:[\\/].* ]]; then
    return 0
  fi

  # For absolute paths, only clean if the resolved location is inside repo_root.
  local abs
  abs="$(realpath "$p" 2>/dev/null || true)"
  [[ -n "$abs" && "$abs" == "$repo_root"* && "$abs" != "$repo_root" ]]
}

if should_cleanup_staging_path "$HOME" || should_cleanup_staging_path "$xdg_config_home"; then
  cleanup_staging=true
fi

if [[ "$cleanup_staging" == "true" ]]; then
  rm -rf "$HOME" "$xdg_config_home" 2>/dev/null || true
fi
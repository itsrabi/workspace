# Source the system bash configuration when available.
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

case $- in
  *i*) ;;
  *) return ;;
esac

__dev_image_statusline_prompt() {
  local cyan='\[\e[36m\]'
  local green='\[\e[32m\]'
  local yellow='\[\e[33m\]'
  local gray='\[\e[90m\]'
  local reset='\[\e[0m\]'

  local display_path="${PWD/#$HOME/\~}"

  local git_segment=""
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local branch
    branch="$(git branch --show-current 2>/dev/null)"
    branch="${branch//$'\n'/}"

    if [[ -z "$branch" ]]; then
      local sha
      sha="$(git rev-parse --short HEAD 2>/dev/null)"
      branch="detached@${sha}"
    fi

    if ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      git_segment="${yellow} [${branch}]${reset}"
    else
      local counts
      counts="$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)"
      if [[ -z "$counts" ]]; then
        git_segment="${gray} [${branch}]${reset}"
      else
        local behind ahead
        read -r behind ahead <<< "$counts"
        if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
          git_segment="${green} [${branch} =]${reset}"
        else
          local seg=""
          if [[ "$ahead" -ne 0 ]]; then seg+=" ↑${ahead}"; fi
          if [[ "$behind" -ne 0 ]]; then seg+=" ↓${behind}"; fi
          git_segment="${yellow} [${branch}${seg}]${reset}"
        fi
      fi
    fi
  fi

  PS1="${cyan}${display_path}${reset}${git_segment}\n> "
}

PROMPT_COMMAND="__dev_image_statusline_prompt"

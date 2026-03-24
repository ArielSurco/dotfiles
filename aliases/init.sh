#!/usr/bin/env zsh
# aliases/init.sh — Source alias files based on enabled groups

# Data directory for all alias configs
export DOTFILES_DATA="$HOME/.dotfiles-data"
[[ -d "$DOTFILES_DATA" ]] || mkdir -p "$DOTFILES_DATA"

# Resolve own directory
_DOTFILES_ALIASES_DIR="${0:A:h}"

# Group registry: group_name -> "file1,file2|Description"
typeset -A _DOTFILES_GROUPS
_DOTFILES_GROUPS=(
  navigation  "gp.sh|Project navigation with TUI menu"
  git         "gsync.sh|Git branch sync across projects"
  kubernetes  "pod.sh,pf.sh|Kubernetes pod connection and port forwarding"
  docker      "dbs.sh|Start local Docker database containers"
  sentry      "sentry.sh|Sentry issue search by custom tags"
  dev         "dev.sh|Configurable project dev launcher"
)

# Core files always loaded (not selectable)
_DOTFILES_CORE_FILES=("utils.sh")

# Source a file with error reporting
_dotfiles_source() {
  local file="$1"
  source "$_DOTFILES_ALIASES_DIR/$file" || echo "Failed to load $file" >&2
}

# Load all alias files
_dotfiles_load() {
  local core_file
  for core_file in "${_DOTFILES_CORE_FILES[@]}"; do
    [[ -f "$_DOTFILES_ALIASES_DIR/$core_file" ]] && _dotfiles_source "$core_file"
  done

  local configfile="$DOTFILES_DATA/enabled-groups"

  if [[ -f "$configfile" ]]; then
    local group_name group_entry files_part file_item
    while IFS= read -r group_name || [[ -n "$group_name" ]]; do
      [[ -z "$group_name" || "$group_name" == \#* ]] && continue
      group_entry="${_DOTFILES_GROUPS[$group_name]}"
      if [[ -n "$group_entry" ]]; then
        files_part="${group_entry%%|*}"
        for file_item in ${(s:,:)files_part}; do
          [[ -f "$_DOTFILES_ALIASES_DIR/$file_item" ]] && _dotfiles_source "$file_item"
        done
      fi
    done < "$configfile"
  else
    local gname gval files_part file_item
    for gname gval in ${(kv)_DOTFILES_GROUPS}; do
      files_part="${gval%%|*}"
      for file_item in ${(s:,:)files_part}; do
        [[ -f "$_DOTFILES_ALIASES_DIR/$file_item" ]] && _dotfiles_source "$file_item"
      done
    done
  fi
}
_dotfiles_load
unfunction _dotfiles_load

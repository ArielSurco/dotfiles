# gp — Dynamic Project Navigation
# Register projects with gp_set, navigate with gp, tab-complete project names.
# Registry: ~/.dotfiles-data/gp-projects (key=path, one per line)

typeset -gA GP_PROJECTS
typeset -ga GP_WATCHES

_gp_load() {
  GP_PROJECTS=()
  local registry="$DOTFILES_DATA/gp-projects"
  [[ -f "$registry" ]] || return 0

  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue
    # Split on first = only
    key="${line%%=*}"
    val="${line#*=}"
    [[ -n "$key" && -n "$val" ]] && GP_PROJECTS[$key]="$val"
  done < "$registry"
}

_gp_save() {
  local tmpfile
  tmpfile="$(mktemp)" || { echo "gp: failed to create temp file" >&2; return 1; }

  local key
  for key in ${(ko)GP_PROJECTS}; do
    echo "${key}=${GP_PROJECTS[$key]}" >> "$tmpfile"
  done

  mv "$tmpfile" "$DOTFILES_DATA/gp-projects" || { echo "gp: failed to save registry" >&2; return 1; }
}

_gp_watches_load() {
  GP_WATCHES=()
  local watchfile="$DOTFILES_DATA/gp-watches"
  [[ -f "$watchfile" ]] || return 0

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    GP_WATCHES+=("$line")
  done < "$watchfile"
}

_gp_watches_save() {
  local tmpfile
  tmpfile="$(mktemp)" || { echo "gp: failed to create temp file" >&2; return 1; }

  # Deduplicate before saving
  local -A seen
  local entry
  for entry in "${GP_WATCHES[@]}"; do
    [[ -n "${seen[$entry]}" ]] && continue
    seen[$entry]=1
    echo "$entry" >> "$tmpfile"
  done

  command mv "$tmpfile" "$DOTFILES_DATA/gp-watches" || { echo "gp: failed to save watches" >&2; return 1; }
}

_gp_scan_dir() {
  local dir="$1"
  local conflict="${2:-ask}"

  local child name existing
  for child in "$dir"/*/(-/N); do
    name="${child:t}"
    existing="${GP_PROJECTS[$name]}"

    if [[ -n "$existing" && "$existing" != "$child" ]]; then
      if [[ "$conflict" == "ask" ]] && command -v gum &>/dev/null; then
        if ! gum confirm "Overwrite '$name'? ($existing → $child)" --default=yes; then
          echo "gp: skipped '$name'" >&2
          continue
        fi
      fi
    fi

    GP_PROJECTS[$name]="$child"
  done
}

gp() {
  if [[ $# -eq 0 ]]; then
    if [[ ${#GP_PROJECTS} -eq 0 ]]; then
      echo "No projects registered. Use gp_set <name> [path] to add one."
      return 0
    fi

    if ! command -v gum &>/dev/null; then
      echo "gp: install gum for interactive selection: brew install gum" >&2
      local key
      for key in ${(ko)GP_PROJECTS}; do
        printf "  %s → %s\n" "$key" "${GP_PROJECTS[$key]}"
      done
      return 0
    fi

    local items=()
    local key
    for key in ${(ko)GP_PROJECTS}; do
      items+=("${key} → ${GP_PROJECTS[$key]}")
    done
    items+=("[Sync projects]")
    items+=("[Delete a project]")

    local selection
    selection=$(printf '%s\n' "${items[@]}" | gum choose --header "Select project:")
    [[ -z "$selection" ]] && return 0

    if [[ "$selection" == "[Sync projects]" ]]; then
      gp_sync
      return 0
    fi

    if [[ "$selection" == "[Delete a project]" ]]; then
      local del_name
      del_name=$(printf '%s\n' ${(ko)GP_PROJECTS} | gum choose --header "Delete which project?")
      [[ -z "$del_name" ]] && return 0

      if gum confirm "Delete '$del_name'?"; then
        unset "GP_PROJECTS[$del_name]"
        _gp_save
        echo "gp: deleted '$del_name'"
      fi
      return 0
    fi

    local name="${selection%% → *}"
    local target="${GP_PROJECTS[$name]}"
    cd "$target"
    return 0
  fi

  local name="$1"
  local target="${GP_PROJECTS[$name]}"

  if [[ -z "$target" ]]; then
    echo "gp: project '$name' not found" >&2
    return 1
  fi

  if [[ ! -d "$target" ]]; then
    echo "gp: directory '$target' does not exist" >&2
    return 1
  fi

  cd "$target"
}

gp_set() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: gp_set <name> [path]" >&2
    return 1
  fi

  local name="$1"
  local dir="${2:-$PWD}"

  # Resolve to absolute path
  dir="${dir:A}"

  if [[ ! -d "$dir" ]]; then
    echo "gp_set: directory '$dir' does not exist" >&2
    return 1
  fi

  GP_PROJECTS[$name]="$dir"
  _gp_save
  echo "gp: registered '$name' → $dir"
}

gp_watch() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: gp_watch <path>" >&2
    return 1
  fi

  local dir="$1"
  dir="${dir:A}"

  if [[ ! -d "$dir" ]]; then
    echo "gp_watch: directory '$dir' does not exist" >&2
    return 1
  fi

  # Deduplicate — skip if already watched
  local p
  for p in "${GP_WATCHES[@]}"; do
    [[ "$p" == "$dir" ]] && {
      _gp_scan_dir "$dir"
      _gp_save
      echo "gp: '$dir' already watched — rescanned"
      return 0
    }
  done

  GP_WATCHES+=("$dir")
  _gp_watches_save
  _gp_scan_dir "$dir"
  _gp_save

  # Count child dirs for summary
  local count=0
  local child
  for child in "$dir"/*/(-/N); do
    (( count++ ))
  done
  echo "gp: watching '$dir' — registered $count projects"
}

gp_sync() {
  _gp_watches_load

  if [[ ${#GP_WATCHES} -eq 0 ]]; then
    echo "No watched folders. Use gp_watch <path> to add one."
    return 0
  fi

  local synced=0 total=0 entry
  for entry in "${GP_WATCHES[@]}"; do
    if [[ ! -d "$entry" ]]; then
      echo "gp_sync: '$entry' no longer exists, skipping" >&2
      continue
    fi
    _gp_scan_dir "$entry"
    (( synced++ ))
  done

  _gp_save
  total=${#GP_PROJECTS}
  echo "gp: synced $synced watched folders, $total projects registered"
}

gp_rm() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: gp_rm <name>" >&2
    return 1
  fi

  local name="$1"
  if [[ -z "${GP_PROJECTS[$name]}" ]]; then
    echo "gp_rm: project '$name' not found" >&2
    return 1
  fi

  unset "GP_PROJECTS[$name]"
  _gp_save
  echo "gp: removed '$name'"
}

_gp_completions() {
  compadd ${(k)GP_PROJECTS}
}
compdef _gp_completions gp

_gp_rm_completions() {
  compadd ${(k)GP_PROJECTS}
}
compdef _gp_rm_completions gp_rm

_gp_watch_completions() {
  _path_files -/
}
compdef _gp_watch_completions gp_watch

# Load registry on source
_gp_load
_gp_watches_load

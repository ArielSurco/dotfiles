# dev — Configurable project dev launcher
# Unified named configs with TUI selection.
# Storage: ~/.dotfiles-data/dev-configs/{name}.sh + projects/

# --- Phase 1: Foundation ---

_dev_config_dir() {
  local dir="$DOTFILES_DATA/dev-configs"
  [[ -d "$dir/projects" ]] || mkdir -p "$dir/projects"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  echo "$dir"
}

_dev_resolve_config() {
  local project="$1"
  local base
  base="$(_dev_config_dir)"

  # Check for .ref first (named config reference)
  if [[ -f "$base/projects/${project}.ref" ]]; then
    local config_name
    config_name="$(< "$base/projects/${project}.ref")"
    local config_path="$base/${config_name}.sh"
    if [[ -f "$config_path" ]]; then
      echo "$config_path"
      return 0
    else
      echo "dev: config '$config_name' not found (referenced by $project)" >&2
      return 1
    fi
  fi

  # Check for override .sh config in projects/
  if [[ -f "$base/projects/${project}.sh" ]]; then
    echo "$base/projects/${project}.sh"
    return 0
  fi

  # No config
  return 1
}

_dev_project_indicator() {
  local project="$1"
  local base
  base="$(_dev_config_dir)"

  if [[ -f "$base/projects/${project}.ref" ]]; then
    local config_name
    config_name="$(< "$base/projects/${project}.ref")"
    echo "[${config_name}]"
  elif [[ -f "$base/projects/${project}.sh" ]]; then
    echo "[custom]"
  fi
}

_dev_config_dependents() {
  local config_name="$1"
  local base
  base="$(_dev_config_dir)/projects"
  local dependents=()
  local ref_file ref_name project_name

  for ref_file in "$base"/*.ref(N); do
    ref_name="$(< "$ref_file")"
    if [[ "$ref_name" == "$config_name" ]]; then
      project_name="${ref_file:t:r}"
      dependents+=("$project_name")
    fi
  done

  if [[ ${#dependents[@]} -gt 0 ]]; then
    printf '%s\n' "${dependents[@]}"
  fi
}

_dev_available_configs() {
  local base
  base="$(_dev_config_dir)"
  local config_names=()
  local cf
  for cf in "$base"/*.sh(N); do
    config_names+=("${cf:t:r}")
  done
  if [[ ${#config_names[@]} -gt 0 ]]; then
    printf '%s\n' "${config_names[@]}"
  fi
}

# --- Phase 2: Core Implementation ---

_dev_run_config() {
  local project="$1"
  local project_dir="${GP_PROJECTS[$project]}"

  if [[ -z "$project_dir" ]]; then
    echo "dev: project '$project' not found in GP_PROJECTS" >&2
    return 1
  fi

  if [[ ! -d "$project_dir" ]]; then
    echo "dev: directory '$project_dir' does not exist" >&2
    return 1
  fi

  local config_path
  config_path="$(_dev_resolve_config "$project")" || return 1

  cd "$project_dir" || return 1
  source "$config_path"
}

_dev_create_flow() {
  local project="$1"
  local base
  base="$(_dev_config_dir)"

  if ! command -v gum &>/dev/null; then
    echo "dev: install gum for interactive config creation: brew install gum" >&2
    return 1
  fi

  local options=("Create new config" "Clone & edit" "Use existing" "Cancel")
  local choice config_names selected name tmpfile

  while true; do
    choice=$(printf '%s\n' "${options[@]}" | gum choose --header "\"$project\" has no dev config.")
    [[ -z "$choice" ]] && return 0

    case "$choice" in
      "Create new config")
        name=$(gum input --placeholder "$project" --header "Config name:")
        [[ -z "$name" ]] && name="$project"

        # Check if already exists
        if [[ -f "$base/${name}.sh" ]]; then
          echo "dev: config '$name' already exists. Use 'dev config edit' to modify." >&2
          continue
        fi

        tmpfile="$(mktemp /tmp/dev-config-XXXXXX.sh)" || return 1
        ${EDITOR:-vi} "$tmpfile"
        if [[ -s "$tmpfile" ]]; then
          command mv "$tmpfile" "$base/${name}.sh"
          echo "$name" > "$base/projects/${project}.ref"
          echo "dev: created config '$name' and linked to '$project'"
        else
          command rm -f "$tmpfile"
          echo "dev: empty config — cancelled"
        fi
        return 0
        ;;
      "Clone & edit")
        config_names=($(_dev_available_configs))
        if [[ ${#config_names[@]} -eq 0 ]]; then
          gum choose --header "No configs available to clone." "← Back"
          continue
        fi

        selected=$(printf '%s\n' "${config_names[@]}" "← Back" | gum choose --header "Clone which config?")
        [[ -z "$selected" || "$selected" == "← Back" ]] && continue

        _dev_clone_and_edit "$selected" "$project"
        return 0
        ;;
      "Use existing")
        config_names=($(_dev_available_configs))
        if [[ ${#config_names[@]} -eq 0 ]]; then
          gum choose --header "No configs available." "← Back"
          continue
        fi

        selected=$(printf '%s\n' "${config_names[@]}" "← Back" | gum choose --header "Select config:")
        [[ -z "$selected" || "$selected" == "← Back" ]] && continue

        echo "$selected" > "$base/projects/${project}.ref"
        echo "dev: '$project' now uses config '$selected'"
        return 0
        ;;
      "Cancel")
        return 0
        ;;
    esac
  done
}

_dev_clone_and_edit() {
  local config_name="$1"
  local project="$2"
  local base
  base="$(_dev_config_dir)"
  local config_path="$base/${config_name}.sh"

  if [[ ! -f "$config_path" ]]; then
    echo "dev: config '$config_name' not found" >&2
    return 1
  fi

  if ! command -v gum &>/dev/null; then
    echo "dev: install gum for interactive config creation: brew install gum" >&2
    return 1
  fi

  local new_name
  new_name=$(gum input --placeholder "$project" --header "Name for the new config:")
  [[ -z "$new_name" ]] && new_name="$project"

  local tmpfile
  tmpfile="$(mktemp /tmp/dev-clone-XXXXXX.sh)" || return 1
  command cp "$config_path" "$tmpfile"

  # Compute checksum before editing
  local checksum_before
  checksum_before=$(shasum -a 256 "$tmpfile" | cut -d' ' -f1)

  ${EDITOR:-vi} "$tmpfile"

  # Compute checksum after editing
  local checksum_after
  checksum_after=$(shasum -a 256 "$tmpfile" | cut -d' ' -f1)

  if [[ "$checksum_before" == "$checksum_after" ]]; then
    # No changes — point to original config
    echo "$config_name" > "$base/projects/${project}.ref"
    command rm -f "$tmpfile"
    echo "dev: no changes made — '$project' now uses config '$config_name'"
  else
    # Changed — save as new named config + ref
    command mv "$tmpfile" "$base/${new_name}.sh"
    echo "$new_name" > "$base/projects/${project}.ref"
    echo "dev: saved config '$new_name' for '$project' (based on '$config_name')"
  fi
}

_dev_config_list() {
  local base
  base="$(_dev_config_dir)"

  local config_files
  config_files=("$base"/*.sh(N))

  if [[ ${#config_files[@]} -eq 0 ]]; then
    if command -v gum &>/dev/null; then
      gum choose --header "No configs found. Use 'dev config create' to add one." "← Back"
    else
      echo "No configs found. Use 'dev config create' to add one."
    fi
    return 0
  fi

  # Build list with project counts
  local items=()
  local cf name deps dep_count
  for cf in "${config_files[@]}"; do
    name="${cf:t:r}"
    deps=$(_dev_config_dependents "$name")
    dep_count=0
    if [[ -n "$deps" ]]; then
      dep_count=$(echo "$deps" | wc -l | tr -d ' ')
    fi
    items+=("$name ($dep_count projects)")
  done

  if ! command -v gum &>/dev/null; then
    echo "Configs:"
    local item
    for item in "${items[@]}"; do
      printf "  %s\n" "$item"
    done
    return 0
  fi

  local selected
  while true; do
    selected=$(printf '%s\n' "${items[@]}" "← Back" | gum choose --header "Configs:")
    [[ -z "$selected" || "$selected" == "← Back" ]] && return 0

    # Extract config name from selection
    name="${selected%% (*}"
    echo ""
    echo "── $name ──"
    cat "$base/${name}.sh"
    echo ""
    echo "Press enter to continue..."
    read -r
  done
}

_dev_config_create() {
  if ! command -v gum &>/dev/null; then
    echo "dev: install gum for interactive config creation: brew install gum" >&2
    return 1
  fi

  local base
  base="$(_dev_config_dir)"

  local name
  name=$(gum input --placeholder "Config name (e.g. ruby-backend)")
  [[ -z "$name" ]] && return 0

  # Check if already exists
  if [[ -f "$base/${name}.sh" ]]; then
    echo "dev: config '$name' already exists. Use 'dev config edit' to modify." >&2
    return 1
  fi

  local tmpfile
  tmpfile="$(mktemp /tmp/dev-config-XXXXXX.sh)" || return 1
  ${EDITOR:-vi} "$tmpfile"

  if [[ -s "$tmpfile" ]]; then
    command mv "$tmpfile" "$base/${name}.sh"
    echo "dev: created config '$name'"
  else
    command rm -f "$tmpfile"
    echo "dev: empty config — cancelled"
  fi
}

_dev_config_edit() {
  local base
  base="$(_dev_config_dir)"

  local config_files
  config_files=("$base"/*.sh(N))

  if ! command -v gum &>/dev/null; then
    echo "dev: install gum for interactive config editing: brew install gum" >&2
    return 1
  fi

  if [[ ${#config_files[@]} -eq 0 ]]; then
    gum choose --header "No configs to edit. Use 'dev config create' first." "← Back"
    return 0
  fi

  local config_names=()
  local cf
  for cf in "${config_files[@]}"; do
    config_names+=("${cf:t:r}")
  done

  local selected
  selected=$(printf '%s\n' "${config_names[@]}" "← Back" | gum choose --header "Edit which config?")
  [[ -z "$selected" || "$selected" == "← Back" ]] && return 0

  ${EDITOR:-vi} "$base/${selected}.sh"
  echo "dev: config '$selected' updated"
}

_dev_config_delete() {
  local base
  base="$(_dev_config_dir)"

  local config_files
  config_files=("$base"/*.sh(N))

  if ! command -v gum &>/dev/null; then
    echo "dev: install gum for interactive config deletion: brew install gum" >&2
    return 1
  fi

  if [[ ${#config_files[@]} -eq 0 ]]; then
    gum choose --header "No configs to delete." "← Back"
    return 0
  fi

  local config_names=()
  local cf
  for cf in "${config_files[@]}"; do
    config_names+=("${cf:t:r}")
  done

  local selected
  selected=$(printf '%s\n' "${config_names[@]}" "← Back" | gum choose --header "Delete which config?")
  [[ -z "$selected" || "$selected" == "← Back" ]] && return 0

  local deps
  deps=$(_dev_config_dependents "$selected")

  if [[ -n "$deps" ]]; then
    local dep_list
    dep_list=$(echo "$deps" | tr '\n' ', ' | command sed 's/,$//')
    echo "dev: config '$selected' is used by: $dep_list"
    if ! gum confirm "Delete config AND remove references for these projects?"; then
      echo "dev: cancelled"
      return 0
    fi
    # Delete all dependent .ref files
    local dep_name
    while IFS= read -r dep_name; do
      command rm -f "$base/projects/${dep_name}.ref"
    done <<< "$deps"
  else
    if ! gum confirm "Delete config '$selected'?"; then
      echo "dev: cancelled"
      return 0
    fi
  fi

  command rm -f "$base/${selected}.sh"
  echo "dev: deleted config '$selected'"
}

_dev_remove_project() {
  local project="$1"
  local base
  base="$(_dev_config_dir)"

  if ! command -v gum &>/dev/null; then
    echo "dev: install gum for interactive removal: brew install gum" >&2
    return 1
  fi

  # Check for .ref (named config reference)
  if [[ -f "$base/projects/${project}.ref" ]]; then
    local config_name
    config_name="$(< "$base/projects/${project}.ref")"

    local deps
    deps=$(_dev_config_dependents "$config_name")
    local other_deps
    other_deps=$(echo "$deps" | while IFS= read -r d; do [[ "$d" != "$project" ]] && echo "$d"; done)

    local options=("Remove config for $project only")
    if [[ -n "$other_deps" ]]; then
      local other_list
      other_list=$(echo "$other_deps" | tr '\n' ', ' | command sed 's/,$//')
      echo "dev: '$project' uses config '$config_name' (also used by: $other_list)"
    fi
    options+=("Delete config $config_name")
    options+=("Cancel")

    local choice
    choice=$(printf '%s\n' "${options[@]}" | gum choose --header "Remove config for '$project':")
    [[ -z "$choice" ]] && return 0

    case "$choice" in
      "Remove config for $project only")
        command rm -f "$base/projects/${project}.ref"
        echo "dev: removed config for '$project'"
        ;;
      "Delete config $config_name")
        # Warn about all dependents
        if [[ -n "$deps" ]]; then
          local all_dep_list
          all_dep_list=$(echo "$deps" | tr '\n' ', ' | command sed 's/,$//')
          echo "dev: this will remove config for: $all_dep_list"
          if ! gum confirm "Proceed with deletion?"; then
            echo "dev: cancelled"
            return 0
          fi
          # Delete all dependent .ref files
          local dep_name
          while IFS= read -r dep_name; do
            command rm -f "$base/projects/${dep_name}.ref"
          done <<< "$deps"
        fi
        command rm -f "$base/${config_name}.sh"
        echo "dev: deleted config '$config_name' and all references"
        ;;
      "Cancel")
        return 0
        ;;
    esac
    return 0
  fi

  # Check for override .sh config
  if [[ -f "$base/projects/${project}.sh" ]]; then
    local options=("Remove config for $project" "Cancel")
    local choice
    choice=$(printf '%s\n' "${options[@]}" | gum choose --header "Remove config for '$project':")
    [[ -z "$choice" ]] && return 0

    case "$choice" in
      "Remove config for $project")
        command rm -f "$base/projects/${project}.sh"
        echo "dev: removed config for '$project'"
        ;;
      "Cancel")
        return 0
        ;;
    esac
    return 0
  fi

  echo "dev: no config found for '$project'" >&2
  return 1
}

# --- Phase 3: Integration ---

dev() {
  if [[ $# -eq 0 ]]; then
    # No args — interactive project selection
    if [[ ${#GP_PROJECTS} -eq 0 ]]; then
      echo "dev: no projects registered. Use gp_set to add projects first." >&2
      return 1
    fi

    if ! command -v gum &>/dev/null; then
      echo "dev: install gum for interactive selection: brew install gum" >&2
      return 1
    fi

    local configured=() unconfigured=()
    local key indicator
    for key in ${(ko)GP_PROJECTS}; do
      indicator=$(_dev_project_indicator "$key")
      if [[ -n "$indicator" ]]; then
        configured+=("$key $indicator")
      else
        unconfigured+=("$key")
      fi
    done

    local items=("${configured[@]}" "${unconfigured[@]}")

    local selection
    selection=$(printf '%s\n' "${items[@]}" | gum choose --header "Select project to dev:")
    [[ -z "$selection" ]] && return 0

    # Extract project name (first word before any indicator)
    local project="${selection%% *}"

    local config_path
    config_path=$(_dev_resolve_config "$project")
    if [[ $? -eq 0 ]]; then
      _dev_run_config "$project"
    else
      _dev_create_flow "$project"
    fi
    return $?
  fi

  # Handle subcommands
  case "$1" in
    config)
      shift
      local subcmd="${1:-}"
      [[ -n "$subcmd" ]] && shift

      case "$subcmd" in
        list)
          _dev_config_list
          ;;
        create)
          _dev_config_create
          ;;
        edit)
          _dev_config_edit
          ;;
        delete)
          _dev_config_delete
          ;;
        "")
          # Interactive config menu
          if ! command -v gum &>/dev/null; then
            echo "Usage: dev config {list|create|edit|delete}" >&2
            return 1
          fi
          local action
          while true; do
            action=$(printf '%s\n' "list" "create" "edit" "delete config" "unlink config from project" | gum choose --header "dev config:")
            [[ -z "$action" ]] && return 0
            case "$action" in
              list)   _dev_config_list ;;
              create) _dev_config_create ;;
              edit)   _dev_config_edit ;;
              "delete config") _dev_config_delete ;;
              "unlink config from project")
                local configured=()
                local key base
                base="$(_dev_config_dir)/projects"
                for key in ${(ko)GP_PROJECTS}; do
                  if [[ -f "$base/${key}.ref" || -f "$base/${key}.sh" ]]; then
                    configured+=("$key")
                  fi
                done
                if [[ ${#configured[@]} -eq 0 ]]; then
                  gum choose --header "No projects have configs to remove." "← Back"
                  continue
                fi
                local project
                project=$(printf '%s\n' "${configured[@]}" "← Back" | gum choose --header "Remove config from:")
                [[ -z "$project" || "$project" == "← Back" ]] && continue
                _dev_remove_project "$project"
                ;;
            esac
          done
          ;;
        *)
          echo "dev config: unknown subcommand '$subcmd'" >&2
          echo "Usage: dev config {list|create|edit|delete}" >&2
          return 1
          ;;
      esac
      ;;
    remove)
      shift
      local project="${1:-}"
      if [[ -z "$project" ]]; then
        if ! command -v gum &>/dev/null; then
          echo "Usage: dev remove <project>" >&2
          return 1
        fi
        # Show only configured projects
        local configured=()
        local key
        for key in ${(ko)GP_PROJECTS}; do
          local base
          base="$(_dev_config_dir)/projects"
          if [[ -f "$base/${key}.ref" || -f "$base/${key}.sh" ]]; then
            configured+=("$key")
          fi
        done
        if [[ ${#configured[@]} -eq 0 ]]; then
          gum choose --header "No projects have configs to remove." "← Back"
          return 0
        fi
        project=$(printf '%s\n' "${configured[@]}" "← Back" | gum choose --header "Remove config from:")
        [[ -z "$project" || "$project" == "← Back" ]] && return 0
      fi
      _dev_remove_project "$project"
      ;;
    *)
      # Treat as project name
      local project="$1"
      if [[ -z "${GP_PROJECTS[$project]}" ]]; then
        echo "dev: project '$project' not found" >&2
        return 1
      fi

      local config_path
      config_path=$(_dev_resolve_config "$project")
      if [[ $? -eq 0 ]]; then
        _dev_run_config "$project"
      else
        _dev_create_flow "$project"
      fi
      ;;
  esac
}

_dev_completions() {
  local -a subcommands
  subcommands=(config remove)

  if [[ ${CURRENT} -eq 2 ]]; then
    # First argument: project names + subcommands
    compadd ${(k)GP_PROJECTS} "${subcommands[@]}"
  elif [[ ${CURRENT} -eq 3 && "${words[2]}" == "config" ]]; then
    compadd list create edit delete
  fi
}
compdef _dev_completions dev

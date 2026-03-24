#!/usr/bin/env zsh
# ai/setup.sh — AI domain setup module, sourced by dotfiles-setup
# Provides: _ai_setup()

_AI_DIR="${0:A:h}/../ai"
# If sourced (not executed directly), resolve relative to this file
if [[ -n "$_SETUP_SCRIPT_DIR" ]]; then
  _AI_DIR="$_SETUP_SCRIPT_DIR/../ai"
fi

_GENERATED_HEADER="<!-- GENERATED FILE — edit source parts in ai/rules/ and ai/parts/, then run setup -->"

_ai_assemble_targets() {
  local target="$1"
  shift
  local parts=("$@")

  # Write header + concatenate all parts
  echo "$_GENERATED_HEADER" > "$target"
  echo "" >> "$target"
  local first=true
  for part in "${parts[@]}"; do
    if [[ ! -f "$part" ]]; then
      echo "  [warn] Part not found: $part"
      continue
    fi
    if [[ "$first" == true ]]; then
      first=false
    else
      echo "" >> "$target"
    fi
    cat "$part" >> "$target"
  done
}

_ai_confirm_overwrite() {
  local target="$1"
  local detail="$2"  # optional extra info (e.g. "was symlink to X")

  local message="$target already exists and is not managed by dotfiles."
  [[ -n "$detail" ]] && message="$target $detail"

  if command -v gum &>/dev/null; then
    local choice
    choice=$(printf '%s\n' "Back up and replace (saves to ${target}.backup.{timestamp})" "Skip (keep existing, configure manually later)" \
      | gum choose --header "$message")
    [[ "$choice" == Back* ]] && return 0
    return 1
  else
    echo "  $message"
    echo "    1. Back up and replace"
    echo "    2. Skip (keep existing)"
    echo -n "  Choose [1/2]: "
    read -r choice
    [[ "$choice" == "1" ]] && return 0
    return 1
  fi
}

_ai_ensure_symlink() {
  local source="$1"
  local target="$2"

  # Create parent directory if needed
  local parent="${target:h}"
  [[ -d "$parent" ]] || mkdir -p "$parent"

  # If target is already the correct symlink, skip
  if [[ -L "$target" ]]; then
    local current_target
    current_target="$(readlink "$target")"
    if [[ "$current_target" == "$source" ]]; then
      echo "  [ok] $target → $source (already correct)"
      return 0
    fi
    # Wrong symlink — ask before replacing
    if _ai_confirm_overwrite "$target" "is a symlink to $current_target, not managed by dotfiles."; then
      local backup="${target}.backup.$(date +%s)"
      mv "$target" "$backup"
      echo "  [backup] $target → $backup (was symlink to $current_target)"
    else
      echo "  [skip] $target (kept existing)"
      return 0
    fi
  elif [[ -e "$target" ]]; then
    # Regular file or directory — ask before replacing
    if _ai_confirm_overwrite "$target"; then
      local backup="${target}.backup.$(date +%s)"
      mv "$target" "$backup"
      echo "  [backup] $target → $backup"
    else
      echo "  [skip] $target (kept existing)"
      return 0
    fi
  fi

  # Create the symlink
  if [[ -d "$source" ]]; then
    ln -sfn "$source" "$target"
  else
    ln -sf "$source" "$target"
  fi
  echo "  [link] $target → $source"
}

_ai_cleanup_deselected() {
  local ai_dir="$1"
  shift
  local -A enabled_tools
  local tname
  for tname in "$@"; do
    enabled_tools[$tname]=1
  done

  local _ai_all_tools=("claude" "cursor")

  for tname in "${_ai_all_tools[@]}"; do
    [[ -n "${enabled_tools[$tname]}" ]] && continue

    case "$tname" in
      claude)
        # Check CLAUDE.md symlink
        local claude_md="$HOME/.claude/CLAUDE.md"
        if [[ -L "$claude_md" ]] && [[ "$(readlink "$claude_md")" == "$ai_dir/"* ]]; then
          if _ai_confirm_overwrite "$claude_md" "points to dotfiles but Claude Code was deselected. Remove managed symlink?"; then
            local backup="${claude_md}.backup.$(date +%s)"
            mv "$claude_md" "$backup"
            echo "  [cleanup] $claude_md → $backup"
          else
            echo "  [keep] $claude_md"
          fi
        fi

        # Check skill symlinks
        local skills_dir="$HOME/.claude/skills"
        if [[ -d "$skills_dir" ]]; then
          for skill_link in "$skills_dir"/*/; do
            [[ -L "${skill_link%/}" ]] || continue
            local link_target
            link_target="$(readlink "${skill_link%/}")"
            if [[ "$link_target" == "$ai_dir/skills/"* ]]; then
              local skill_path="${skill_link%/}"
              if _ai_confirm_overwrite "$skill_path" "points to dotfiles but Claude Code was deselected. Remove managed symlink?"; then
                local backup="${skill_path}.backup.$(date +%s)"
                mv "$skill_path" "$backup"
                echo "  [cleanup] $skill_path → $backup"
              else
                echo "  [keep] $skill_path"
              fi
            fi
          done
        fi
        ;;
      cursor)
        local cursor_mdc="$HOME/.cursor/rules/gentle-ai.mdc"
        if [[ -L "$cursor_mdc" ]] && [[ "$(readlink "$cursor_mdc")" == "$ai_dir/"* ]]; then
          if _ai_confirm_overwrite "$cursor_mdc" "points to dotfiles but Cursor was deselected. Remove managed symlink?"; then
            local backup="${cursor_mdc}.backup.$(date +%s)"
            mv "$cursor_mdc" "$backup"
            echo "  [cleanup] $cursor_mdc → $backup"
          else
            echo "  [keep] $cursor_mdc"
          fi
        fi
        ;;
    esac
  done
}

_ai_setup() {
  echo ""
  echo "AI Setup"
  echo "--------"

  # Ensure DOTFILES_DATA is set (fallback for standalone sourcing)
  : "${DOTFILES_DATA:=$HOME/.dotfiles-data}"
  [[ -d "$DOTFILES_DATA" ]] || mkdir -p "$DOTFILES_DATA"

  # Resolve absolute path
  local ai_dir="${_AI_DIR:A}"

  # Step 1: Assemble targets (always runs — generates files in ai/targets/)
  echo ""
  echo "Assembling targets..."

  _ai_assemble_targets "$ai_dir/targets/claude.md" \
    "$ai_dir/parts/engram-protocol.md" \
    "$ai_dir/rules/persona.md" \
    "$ai_dir/parts/sdd-orchestrator.md"
  echo "  [ok] ai/targets/claude.md"

  _ai_assemble_targets "$ai_dir/targets/cursor.mdc" \
    "$ai_dir/parts/engram-protocol.md" \
    "$ai_dir/rules/persona.md"
  echo "  [ok] ai/targets/cursor.mdc"

  # Step 2: Tool selection
  echo ""
  echo "Select your AI tools:"
  echo ""

  local _ai_tools_file="$DOTFILES_DATA/enabled-ai-tools"

  # Tool definitions
  local _ai_tool_order=("claude" "cursor")
  typeset -A _ai_tool_labels
  _ai_tool_labels[claude]="Claude Code"
  _ai_tool_labels[cursor]="Cursor"

  # Read current selection if exists
  typeset -A _ai_current_tools
  if [[ -f "$_ai_tools_file" ]]; then
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      _ai_current_tools[$line]=1
    done < "$_ai_tools_file"
  fi

  local _ai_selected_tools=()

  if command -v gum &>/dev/null; then
    local items=()
    local preselected=()
    local tname
    for tname in "${_ai_tool_order[@]}"; do
      local label="${_ai_tool_labels[$tname]}"
      items+=("$tname — $label")
      # Pre-select only from saved config (first run = none selected)
      if [[ -f "$_ai_tools_file" ]] && [[ -n "${_ai_current_tools[$tname]}" ]]; then
        preselected+=("$tname — $label")
      fi
    done

    local selected
    if [[ ${#preselected} -gt 0 ]]; then
      selected=$(printf '%s\n' "${items[@]}" | gum choose --no-limit --header "Select AI tools (space to toggle, enter to confirm):" --selected="$(printf '%s,' "${preselected[@]}")")
    else
      selected=$(printf '%s\n' "${items[@]}" | gum choose --no-limit --header "Select AI tools (space to toggle, enter to confirm):")
    fi

    if [[ -z "$selected" ]]; then
      echo "No AI tools selected. Skipping symlinks."
      echo ""
      echo "# Enabled AI tools" > "$_ai_tools_file"
      echo ""
      echo "AI setup complete (targets assembled, no symlinks created)."
      return 0
    fi

    # Parse selected — extract tool names (before " — ")
    echo "# Enabled AI tools" > "$_ai_tools_file"
    echo "$selected" | while IFS= read -r line; do
      local tname="${line%% — *}"
      echo "$tname" >> "$_ai_tools_file"
      _ai_selected_tools+=("$tname")
    done

  else
    # Fallback: numbered list with manual input
    echo "gum not found — using text mode"
    echo ""
    local tnames=()
    local idx=1
    local tname
    for tname in "${_ai_tool_order[@]}"; do
      local marker=" "
      if [[ -f "$_ai_tools_file" ]] && [[ -n "${_ai_current_tools[$tname]}" ]]; then
        marker="*"
      fi
      echo "  [$marker] $idx. ${_ai_tool_labels[$tname]}"
      tnames+=("$tname")
      (( idx++ ))
    done
    echo ""
    echo "Enter tool numbers to enable (comma-separated, e.g. 1,2):"
    echo -n "> "
    read -r selection

    if [[ -z "$selection" ]]; then
      echo "No AI tools selected. Skipping symlinks."
      echo ""
      echo "# Enabled AI tools" > "$_ai_tools_file"
      echo ""
      echo "AI setup complete (targets assembled, no symlinks created)."
      return 0
    fi

    echo "# Enabled AI tools" > "$_ai_tools_file"
    local num
    for num in ${(s:,:)selection}; do
      num="${num## }" ; num="${num%% }"
      if [[ "$num" -ge 1 && "$num" -le ${#tnames} ]]; then
        echo "${tnames[$num]}" >> "$_ai_tools_file"
        _ai_selected_tools+=("${tnames[$num]}")
      fi
    done
  fi

  echo ""
  echo "Selected tools:"
  for tname in "${_ai_selected_tools[@]}"; do
    echo "  + ${_ai_tool_labels[$tname]}"
  done

  # Step 3: Create symlinks (only for selected tools)
  echo ""
  echo "Creating symlinks..."

  # Check if a tool is selected
  typeset -A _ai_enabled
  for tname in "${_ai_selected_tools[@]}"; do
    _ai_enabled[$tname]=1
  done

  # Claude Code symlinks
  if [[ -n "${_ai_enabled[claude]}" ]]; then
    local skills_target="$HOME/.claude/skills"
    if [[ -L "$skills_target" ]]; then
      echo "  [migrate] $skills_target is a symlink, converting to real directory..."
      rm "$skills_target"
    fi
    [[ -d "$skills_target" ]] || mkdir -p "$skills_target"

    for skill_dir in "$ai_dir/skills"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name="${skill_dir:t}"
      _ai_ensure_symlink "${skill_dir%/}" "$skills_target/$skill_name"
    done
    _ai_ensure_symlink "$ai_dir/targets/claude.md" "$HOME/.claude/CLAUDE.md"
  fi

  # Cursor symlinks
  if [[ -n "${_ai_enabled[cursor]}" ]]; then
    _ai_ensure_symlink "$ai_dir/targets/cursor.mdc" "$HOME/.cursor/rules/gentle-ai.mdc"
  fi

  # Step 4: Clean up symlinks for deselected tools
  echo ""
  echo "Checking for deselected tools..."
  _ai_cleanup_deselected "$ai_dir" "${_ai_selected_tools[@]}"

  echo ""
  echo "AI setup complete."
}

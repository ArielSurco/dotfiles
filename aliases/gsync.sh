# gsync — Git sync utility for registered projects
# Syncs configured branches across project repositories
# Config: ~/.dotfiles-data/gsync-branches (one branch per line)

typeset -ga GSYNC_BRANCHES

_gsync_branches_load() {
  GSYNC_BRANCHES=()
  local configfile="$DOTFILES_DATA/gsync-branches"
  if [[ ! -f "$configfile" ]]; then
    GSYNC_BRANCHES=(main master)
    return 0
  fi
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    GSYNC_BRANCHES+=("$line")
  done < "$configfile"
  [[ ${#GSYNC_BRANCHES} -eq 0 ]] && GSYNC_BRANCHES=(main master)
}

_gsync_branches_save() {
  local tmpfile
  tmpfile="$(mktemp)" || { echo "gsync: failed to create temp file" >&2; return 1; }
  local -A seen
  local entry
  for entry in "${GSYNC_BRANCHES[@]}"; do
    [[ -n "${seen[$entry]}" ]] && continue
    seen[$entry]=1
    echo "$entry" >> "$tmpfile"
  done
  command mv "$tmpfile" "$DOTFILES_DATA/gsync-branches" || { echo "gsync: failed to save config" >&2; return 1; }
}

gsync_set() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: gsync_set <branch...>" >&2
    return 1
  fi
  local branch_name
  for branch_name in "$@"; do
    local existing
    local found=0
    for existing in "${GSYNC_BRANCHES[@]}"; do
      [[ "$existing" == "$branch_name" ]] && { found=1; break; }
    done
    if [[ $found -eq 0 ]]; then
      GSYNC_BRANCHES+=("$branch_name")
    fi
  done
  _gsync_branches_save
  echo "gsync: branches configured: ${GSYNC_BRANCHES[*]}"
}

gsync_rm() {
  if [[ ${#GSYNC_BRANCHES} -eq 0 ]]; then
    echo "gsync: no branches configured" >&2
    return 1
  fi

  local target="$1"

  if [[ -z "$target" ]]; then
    if command -v gum &>/dev/null; then
      target=$(printf '%s\n' "${GSYNC_BRANCHES[@]}" | gum choose --header "Remove which branch?")
      [[ -z "$target" ]] && return 0
    else
      echo "Usage: gsync_rm <branch>" >&2
      return 1
    fi
  fi

  local new_branches=()
  local found=0
  local entry
  for entry in "${GSYNC_BRANCHES[@]}"; do
    if [[ "$entry" == "$target" ]]; then
      found=1
    else
      new_branches+=("$entry")
    fi
  done

  if [[ $found -eq 0 ]]; then
    echo "gsync_rm: branch '$target' not in config" >&2
    return 1
  fi

  GSYNC_BRANCHES=("${new_branches[@]}")
  _gsync_branches_save
  echo "gsync: removed '$target'"
}

gsync_list() {
  if [[ ${#GSYNC_BRANCHES} -eq 0 ]]; then
    echo "No branches configured (defaults: main master)"
    return 0
  fi
  echo "Configured branches:"
  local entry
  for entry in "${GSYNC_BRANCHES[@]}"; do
    echo "  $entry"
  done
}

_gsync_resolve_project() {
  local arg="$1"

  if [[ -n "$arg" ]]; then
    local proj_dir="${GP_PROJECTS[$arg]}"
    if [[ -z "$proj_dir" ]]; then
      echo "gsync: project '$arg' not found" >&2
      return 1
    fi
    echo "$proj_dir"
    return 0
  fi

  # Match $PWD against GP_PROJECTS values
  local key
  for key in ${(k)GP_PROJECTS}; do
    if [[ "${GP_PROJECTS[$key]}" == "$PWD" ]]; then
      echo "$PWD"
      return 0
    fi
  done

  # Fallback: if current dir is a git repo, use it even if not registered
  if [[ -d "$PWD/.git" ]]; then
    echo "$PWD"
    return 0
  fi

  echo "gsync: current directory is not a registered project or git repo" >&2
  return 1
}

_gsync_repo() {
  local proj_dir="$1"
  local orig_dir="$PWD"

  cd "$proj_dir" || { echo "gsync: cannot cd to '$proj_dir'" >&2; return 1; }

  if [[ ! -d ".git" ]]; then
    echo "gsync: '$proj_dir' is not a git repo" >&2
    cd "$orig_dir"
    return 1
  fi

  echo "Syncing $(basename "$proj_dir")..."

  # Fetch all remotes
  if ! git fetch --all --prune 2>/dev/null; then
    echo "gsync: fetch failed (network error?)" >&2
    cd "$orig_dir"
    return 1
  fi

  # Check dirty working tree
  local stashed=0
  local dirty
  dirty=$(git status --porcelain 2>/dev/null)
  if [[ -n "$dirty" ]]; then
    echo "  Working tree has uncommitted changes"
    if command -v gum &>/dev/null; then
      if gum confirm "Stash changes before syncing?"; then
        git stash push -m "gsync: auto-stash" || { echo "gsync: stash failed" >&2; cd "$orig_dir"; return 1; }
        stashed=1
      else
        echo "  Skipping sync (dirty tree)" >&2
        cd "$orig_dir"
        return 0
      fi
    else
      echo "gsync: install gum to handle dirty working tree: brew install gum" >&2
      echo "  Skipping sync (dirty tree)" >&2
      cd "$orig_dir"
      return 0
    fi
  fi

  local current_branch
  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)

  local branch_name
  for branch_name in "${GSYNC_BRANCHES[@]}"; do
    # Check if branch exists locally or in remote
    if ! git rev-parse --verify "$branch_name" &>/dev/null; then
      # Check if remote branch exists
      if git rev-parse --verify "origin/$branch_name" &>/dev/null; then
        git branch --track "$branch_name" "origin/$branch_name" &>/dev/null
      else
        continue
      fi
    fi

    # Check remote tracking exists
    if ! git rev-parse --verify "origin/$branch_name" &>/dev/null; then
      continue
    fi

    local local_sha remote_sha
    local_sha=$(git rev-parse "$branch_name" 2>/dev/null)
    remote_sha=$(git rev-parse "origin/$branch_name" 2>/dev/null)

    if [[ "$local_sha" == "$remote_sha" ]]; then
      echo "  $branch_name: up to date"
      continue
    fi

    if [[ "$branch_name" == "$current_branch" ]]; then
      # Current branch — use pull
      if git merge-base --is-ancestor "$local_sha" "$remote_sha"; then
        git pull --ff-only 2>/dev/null
        echo "  $branch_name: fast-forwarded (current)"
      else
        echo "  $branch_name: diverged from origin"
        if command -v gum &>/dev/null; then
          if gum confirm "Reset '$branch_name' to origin/$branch_name? (git reset --hard)" --default=no; then
            git reset --hard "origin/$branch_name"
            echo "  $branch_name: reset to origin"
          else
            echo "  $branch_name: skipped (diverged)"
          fi
        else
          echo "  $branch_name: skipped — diverged, install gum to resolve" >&2
        fi
      fi
    else
      # Other branch — use update-ref
      if git merge-base --is-ancestor "$local_sha" "$remote_sha"; then
        git update-ref "refs/heads/$branch_name" "$remote_sha"
        echo "  $branch_name: fast-forwarded"
      else
        echo "  $branch_name: diverged from origin"
        if command -v gum &>/dev/null; then
          if gum confirm "Force update '$branch_name' to origin/$branch_name?" --default=no; then
            git update-ref "refs/heads/$branch_name" "$remote_sha"
            echo "  $branch_name: force updated to origin"
          else
            echo "  $branch_name: skipped (diverged)"
          fi
        else
          echo "  $branch_name: skipped — diverged, install gum to resolve" >&2
        fi
      fi
    fi
  done

  # Restore stash if we stashed
  if [[ $stashed -eq 1 ]]; then
    if ! git stash pop 2>/dev/null; then
      echo "  WARNING: stash pop had conflicts — your changes are in 'git stash list'" >&2
    else
      echo "  Restored stashed changes"
    fi
  fi

  cd "$orig_dir"
}

gsync() {
  local proj_dir
  proj_dir=$(_gsync_resolve_project "$1") || return 1
  _gsync_branches_load
  _gsync_repo "$proj_dir"
}

_gsync_completions() {
  compadd ${(k)GP_PROJECTS}
}
compdef _gsync_completions gsync

_gsync_rm_completions() {
  compadd "${GSYNC_BRANCHES[@]}"
}
compdef _gsync_rm_completions gsync_rm

# Load config on source
_gsync_branches_load

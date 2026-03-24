#!/usr/bin/env bats
# Tests for aliases/gsync.sh — Git Branch Sync

GP_SCRIPT="/Users/arielsurco/dotfiles/aliases/gp.sh"
GSYNC_SCRIPT="/Users/arielsurco/dotfiles/aliases/gsync.sh"

setup() {
  export TEST_HOME="$(/bin/zsh -c "d=\$(mktemp -d); echo \${d:A}")"
  export REAL_HOME="$HOME"
  export HOME="$TEST_HOME"
  export ORIG_PATH="$PATH"

  mkdir -p "$TEST_HOME/projects/alpha"
  mkdir -p "$TEST_HOME/projects/beta"
}

teardown() {
  export HOME="$REAL_HOME"
  export PATH="$ORIG_PATH"
  rm -rf "$TEST_HOME"
}

# Helper: run a gsync command in zsh with controlled HOME
gsync_run() {
  env HOME="$TEST_HOME" /bin/zsh -c "export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"; source '$GP_SCRIPT' && source '$GSYNC_SCRIPT' && $*"
}

# Helper: PATH without /opt/homebrew/bin (excludes gum)
path_no_gum() {
  echo "$ORIG_PATH" | tr ':' '\n' | while read -r p; do
    [[ "$p" != */homebrew/bin ]] && printf '%s:' "$p"
  done | sed 's/:$//'
}

# Helper: create a bare repo + clone with an initial commit
create_repo_with_origin() {
  local bare_path="$1"
  local clone_path="$2"

  git init --bare "$bare_path" 2>/dev/null
  git clone "$bare_path" "$clone_path" 2>/dev/null
  cd "$clone_path"
  # Force branch to be called main regardless of git defaults
  git checkout -b main 2>/dev/null || true
  git commit --allow-empty -m "initial" 2>/dev/null
  git push -u origin main 2>/dev/null
  cd - >/dev/null
}

# ---------------------------------------------------------------------------
# gsync_list — List configured branches
# ---------------------------------------------------------------------------

@test "gsync_list shows defaults when no config" {
  run gsync_run "gsync_list"
  [ "$status" -eq 0 ]
  [[ "$output" == *"main"* ]]
  [[ "$output" == *"master"* ]]
}

# ---------------------------------------------------------------------------
# gsync_set — Add branches to config
# ---------------------------------------------------------------------------

@test "gsync_set adds branches" {
  run gsync_run "gsync_set develop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"develop"* ]]

  # Verify config file contains develop
  [[ "$(< "$TEST_HOME/.dotfiles-data/gsync-branches")" == *"develop"* ]]
}

@test "gsync_set deduplicates" {
  run gsync_run "gsync_set main && gsync_set main"
  [ "$status" -eq 0 ]

  local count
  count=$(rg -c '^main$' "$TEST_HOME/.dotfiles-data/gsync-branches" 2>/dev/null || echo "0")
  [ "$count" -le 1 ]
}

@test "gsync_set without args shows error" {
  run gsync_run "gsync_set"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

# ---------------------------------------------------------------------------
# gsync_rm — Remove branches from config
# ---------------------------------------------------------------------------

@test "gsync_rm removes branch from config" {
  run gsync_run "gsync_set develop && gsync_rm develop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed 'develop'"* ]]

  if [ -f "$TEST_HOME/.dotfiles-data/gsync-branches" ]; then
    [[ "$(< "$TEST_HOME/.dotfiles-data/gsync-branches")" != *"develop"* ]]
  fi
}

@test "gsync_rm with unknown branch shows error" {
  run gsync_run "gsync_rm nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in config"* ]]
}

@test "gsync_rm without args and no gum shows error" {
  local nogum_path
  nogum_path="$(path_no_gum)"

  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='$nogum_path'
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    source '$GP_SCRIPT'
    source '$GSYNC_SCRIPT'
    gsync_rm
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

# ---------------------------------------------------------------------------
# gsync — Project resolution
# ---------------------------------------------------------------------------

@test "gsync with unknown project shows error" {
  run gsync_run "gsync nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "gsync resolves project from GP_PROJECTS" {
  # Register a project, then try to gsync it
  # It will fail on fetch (no remote) but should resolve the project first
  cd "$TEST_HOME/projects/alpha"
  git init . 2>/dev/null
  cd - >/dev/null

  run gsync_run "gp_set alpha '$TEST_HOME/projects/alpha' && gsync alpha"
  # It should find the project (not "not found") but may fail on fetch
  [[ "$output" != *"not found"* ]]
  [[ "$output" == *"Syncing alpha"* ]] || [[ "$output" == *"fetch failed"* ]]
}

@test "gsync on non-git directory shows error" {
  run gsync_run "gp_set beta '$TEST_HOME/projects/beta' && gsync beta"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repo"* ]]
}

# ---------------------------------------------------------------------------
# gsync — Core sync with real git repo
# ---------------------------------------------------------------------------

@test "gsync syncs clean repo with fast-forwardable branch" {
  local bare="$TEST_HOME/origin.git"
  local clone1="$TEST_HOME/projects/myrepo"
  local clone2="$TEST_HOME/clone2"

  create_repo_with_origin "$bare" "$clone1"

  # Create a second clone and push an ahead commit
  git clone "$bare" "$clone2" 2>/dev/null
  cd "$clone2"
  # Ensure we're on main (not master)
  git checkout main 2>/dev/null || git checkout -b main 2>/dev/null
  git commit --allow-empty -m "ahead commit" 2>/dev/null
  git push origin main 2>/dev/null
  cd - >/dev/null

  # Now clone1 is behind origin — gsync should fast-forward
  run env HOME="$TEST_HOME" /bin/zsh -c "
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    source '$GP_SCRIPT'
    source '$GSYNC_SCRIPT'
    gp_set myrepo '$clone1' >/dev/null 2>&1
    gsync myrepo
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-forwarded"* ]]
}

@test "gsync detects dirty working tree" {
  local bare="$TEST_HOME/origin.git"
  local clone1="$TEST_HOME/projects/dirtyrepo"

  create_repo_with_origin "$bare" "$clone1"

  # Make the working tree dirty
  echo "dirty" > "$clone1/untracked.txt"
  cd "$clone1" && git add untracked.txt 2>/dev/null
  cd - >/dev/null

  local nogum_path
  nogum_path="$(path_no_gum)"

  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='$nogum_path'
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    source '$GP_SCRIPT'
    source '$GSYNC_SCRIPT'
    gp_set dirtyrepo '$clone1' >/dev/null 2>&1
    gsync dirtyrepo
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirty tree"* ]] || [[ "$output" == *"uncommitted changes"* ]]
}

# ---------------------------------------------------------------------------
# PATH safety — regression tests
# ---------------------------------------------------------------------------

@test "PATH is not corrupted after _gsync_branches_load" {
  run env HOME="$TEST_HOME" PATH="$ORIG_PATH" /bin/zsh -c "
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    source '$GP_SCRIPT'
    source '$GSYNC_SCRIPT'
    _gsync_branches_load
    command -v mv
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"/mv"* ]]
}

@test "PATH is not corrupted after _gsync_branches_save" {
  run env HOME="$TEST_HOME" PATH="$ORIG_PATH" /bin/zsh -c "
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    source '$GP_SCRIPT'
    source '$GSYNC_SCRIPT'
    _gsync_branches_save
    command -v mv
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"/mv"* ]]
}

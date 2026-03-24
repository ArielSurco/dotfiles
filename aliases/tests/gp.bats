#!/usr/bin/env bats
# Tests for aliases/gp.sh — Dynamic Project Navigation

GP_SCRIPT="/Users/arielsurco/dotfiles/aliases/gp.sh"

setup() {
  # Resolve through /private to match zsh :A behavior on macOS
  export TEST_HOME="$(/bin/zsh -c "d=\$(mktemp -d); echo \${d:A}")"
  export REAL_HOME="$HOME"
  export HOME="$TEST_HOME"
  export ORIG_PATH="$PATH"

  # Create test directories
  mkdir -p "$TEST_HOME/projects/alpha"
  mkdir -p "$TEST_HOME/projects/beta"
  mkdir -p "$TEST_HOME/projects/gamma"
  mkdir -p "$TEST_HOME/single-project"
}

teardown() {
  export HOME="$REAL_HOME"
  export PATH="$ORIG_PATH"
  rm -rf "$TEST_HOME"
}

# Helper: run a gp command in zsh with controlled HOME
gp_run() {
  env HOME="$TEST_HOME" /bin/zsh -c "export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"; source '$GP_SCRIPT' && $*"
}

# Helper: PATH without /opt/homebrew/bin (excludes gum)
path_no_gum() {
  echo "$ORIG_PATH" | tr ':' '\n' | while read -r p; do
    [[ "$p" != */homebrew/bin ]] && printf '%s:' "$p"
  done | sed 's/:$//'
}

# ---------------------------------------------------------------------------
# gp_set — Basic registration
# ---------------------------------------------------------------------------

@test "gp_set registers project with explicit path" {
  run gp_run "gp_set foo '$TEST_HOME/single-project'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"registered 'foo'"* ]]

  # Verify registry file
  [[ "$(< "$TEST_HOME/.dotfiles-data/gp-projects")" == *"foo=$TEST_HOME/single-project"* ]]
}

@test "gp_set registers project with current directory" {
  run gp_run "cd '$TEST_HOME/single-project' && gp_set myproj"
  [ "$status" -eq 0 ]
  [[ "$output" == *"registered 'myproj'"* ]]

  [[ "$(< "$TEST_HOME/.dotfiles-data/gp-projects")" == *"myproj=$TEST_HOME/single-project"* ]]
}

@test "gp_set without args shows error" {
  run gp_run "gp_set"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "gp_set with non-existent directory shows error" {
  run gp_run "gp_set bad '/no/such/path'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

# ---------------------------------------------------------------------------
# gp — Navigation
# ---------------------------------------------------------------------------

@test "gp navigates to registered project" {
  run gp_run "gp_set alpha '$TEST_HOME/projects/alpha' && gp alpha && pwd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_HOME/projects/alpha"* ]]
}

@test "gp with unknown project shows error" {
  run gp_run "gp nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "gp with deleted directory shows error" {
  run gp_run "gp_set gone '$TEST_HOME/single-project' && rm -rf '$TEST_HOME/single-project' && gp gone"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

# ---------------------------------------------------------------------------
# gp — Listing (no gum available)
# ---------------------------------------------------------------------------

@test "gp with no args lists projects when gum not available" {
  local nogum_path
  nogum_path="$(path_no_gum)"

  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='$nogum_path'
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    source '$GP_SCRIPT'
    gp_set alpha '$TEST_HOME/projects/alpha' >/dev/null 2>&1
    gp_set beta '$TEST_HOME/projects/beta' >/dev/null 2>&1
    gp
  "
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "gp with no args and no projects shows helpful message" {
  local nogum_path
  nogum_path="$(path_no_gum)"

  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='$nogum_path'
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    source '$GP_SCRIPT' 2>/dev/null
    gp
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"No projects registered"* ]]
}

# ---------------------------------------------------------------------------
# gp_watch — Watch directories
# ---------------------------------------------------------------------------

@test "gp_watch scans child directories" {
  run gp_run "gp_watch '$TEST_HOME/projects'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"watching"* ]]
  [[ "$output" == *"3 projects"* ]]

  # Verify all children registered
  local contents
  contents="$(< "$TEST_HOME/.dotfiles-data/gp-projects")"
  [[ "$contents" == *"alpha="* ]]
  [[ "$contents" == *"beta="* ]]
  [[ "$contents" == *"gamma="* ]]
}

@test "gp_watch without args shows error" {
  run gp_run "gp_watch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "gp_watch persists watched path" {
  run gp_run "gp_watch '$TEST_HOME/projects'"
  [ "$status" -eq 0 ]

  local contents
  contents="$(< "$TEST_HOME/.dotfiles-data/gp-watches")"
  [[ "$contents" == *"$TEST_HOME/projects"* ]]
}

@test "gp_watch on non-existent directory shows error" {
  run gp_run "gp_watch '/no/such/dir'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "gp_watch deduplicates already-watched directories" {
  run gp_run "gp_watch '$TEST_HOME/projects' && gp_watch '$TEST_HOME/projects'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already watched"* ]]

  # Count lines in watches file — should be exactly 1
  local line_count
  line_count=$(wc -l < "$TEST_HOME/.dotfiles-data/gp-watches" | tr -d ' ')
  [ "$line_count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# gp_sync — Rescan watches
# ---------------------------------------------------------------------------

@test "gp_sync re-scans watched folders and picks up new projects" {
  gp_run "gp_watch '$TEST_HOME/projects'"
  mkdir -p "$TEST_HOME/projects/delta"

  run gp_run "gp_sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"synced"* ]]

  local contents
  contents="$(< "$TEST_HOME/.dotfiles-data/gp-projects")"
  [[ "$contents" == *"delta="* ]]
}

@test "gp_sync handles stale watched path without crashing" {
  gp_run "gp_watch '$TEST_HOME/projects'"
  rm -rf "$TEST_HOME/projects"

  run gp_run "gp_sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no longer exists"* ]]
}

@test "gp_sync with no watches shows message" {
  run gp_run "gp_sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No watched folders"* ]]
}

# ---------------------------------------------------------------------------
# gp_rm — Remove projects
# ---------------------------------------------------------------------------

@test "gp_rm removes registered project" {
  gp_run "gp_set killme '$TEST_HOME/single-project'"

  run gp_run "gp_rm killme"
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed 'killme'"* ]]

  # Verify gone from registry
  if [ -f "$TEST_HOME/.dotfiles-data/gp-projects" ]; then
    [[ "$(< "$TEST_HOME/.dotfiles-data/gp-projects")" != *"killme"* ]]
  fi
}

@test "gp_rm with unknown project shows error" {
  run gp_run "gp_rm ghost"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "gp_rm without args shows error" {
  run gp_run "gp_rm"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

# ---------------------------------------------------------------------------
# PATH safety — regression tests
# ---------------------------------------------------------------------------

@test "PATH is not corrupted after _gp_watches_save" {
  run env HOME="$TEST_HOME" PATH="$ORIG_PATH" /bin/zsh -c "
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    source '$GP_SCRIPT'
    _gp_watches_save
    command -v mv
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"/mv"* ]]
}

@test "PATH is not corrupted after gp_sync" {
  run env HOME="$TEST_HOME" PATH="$ORIG_PATH" /bin/zsh -c "
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    source '$GP_SCRIPT'
    gp_sync
    command -v mv
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"/mv"* ]]
}

@test "PATH is not corrupted after _gp_load" {
  run env HOME="$TEST_HOME" PATH="$ORIG_PATH" /bin/zsh -c "
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    source '$GP_SCRIPT'
    _gp_load
    command -v mv
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"/mv"* ]]
}

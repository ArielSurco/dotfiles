#!/usr/bin/env bats
# Tests for aliases/init.sh — Group-based sourcing and dotfiles-setup

INIT_SCRIPT="/Users/arielsurco/dotfiles/aliases/init.sh"
SETUP_SCRIPT="/Users/arielsurco/dotfiles/bin/dotfiles-setup"

setup() {
  export TEST_HOME="$(/bin/zsh -c "d=\$(mktemp -d); echo \${d:A}")"
  export REAL_HOME="$HOME"
  export HOME="$TEST_HOME"
  export ORIG_PATH="$PATH"
  mkdir -p "$TEST_HOME/.dotfiles-data"
}

teardown() {
  export HOME="$REAL_HOME"
  export PATH="$ORIG_PATH"
  rm -rf "$TEST_HOME"
}

# Helper: source init.sh in a controlled zsh environment
# Stub compdef since completion system isn't loaded in test environment
init_run() {
  env HOME="$TEST_HOME" /bin/zsh -c "compdef() { :; }; source '$INIT_SCRIPT' && $*"
}

# ---------------------------------------------------------------------------
# DOTFILES_DATA is set after sourcing init.sh
# ---------------------------------------------------------------------------
@test "DOTFILES_DATA is exported after sourcing init.sh" {
  run init_run 'echo "$DOTFILES_DATA"'
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_HOME/.dotfiles-data" ]
}

# ---------------------------------------------------------------------------
# DOTFILES_DATA directory is created if missing
# ---------------------------------------------------------------------------
@test "DOTFILES_DATA directory is created if it does not exist" {
  rm -rf "$TEST_HOME/.dotfiles-data"
  run init_run '[[ -d "$DOTFILES_DATA" ]] && echo "exists"'
  [ "$status" -eq 0 ]
  [ "$output" = "exists" ]
}

# ---------------------------------------------------------------------------
# All groups loaded when no config file exists (backwards compatible)
# ---------------------------------------------------------------------------
@test "all groups loaded when no enabled-groups config exists" {
  # gp function should exist (navigation group)
  run init_run 'typeset -f gp >/dev/null && echo "gp_ok"'
  [ "$status" -eq 0 ]
  [ "$output" = "gp_ok" ]
}

@test "gsync loaded when no config exists" {
  run init_run 'typeset -f gsync >/dev/null && echo "gsync_ok"'
  [ "$status" -eq 0 ]
  [ "$output" = "gsync_ok" ]
}

# ---------------------------------------------------------------------------
# Selective loading: only enabled groups are sourced
# ---------------------------------------------------------------------------
@test "only navigation group loaded when config has only navigation" {
  echo "navigation" > "$TEST_HOME/.dotfiles-data/enabled-groups"
  # gp should exist
  run init_run 'typeset -f gp >/dev/null && echo "gp_ok"'
  [ "$status" -eq 0 ]
  [ "$output" = "gp_ok" ]
}

@test "gsync NOT loaded when config has only navigation" {
  echo "navigation" > "$TEST_HOME/.dotfiles-data/enabled-groups"
  run init_run 'typeset -f gsync >/dev/null && echo "gsync_ok" || echo "gsync_missing"'
  [ "$status" -eq 0 ]
  [ "$output" = "gsync_missing" ]
}

# ---------------------------------------------------------------------------
# Core files always loaded regardless of config
# ---------------------------------------------------------------------------
@test "core utils loaded even with selective config" {
  echo "navigation" > "$TEST_HOME/.dotfiles-data/enabled-groups"
  # utils.sh defines dotalias function
  run init_run 'typeset -f dotalias >/dev/null && echo "dotalias_ok" || echo "dotalias_missing"'
  [ "$status" -eq 0 ]
  [ "$output" = "dotalias_ok" ]
}

# ---------------------------------------------------------------------------
# Config file with comments and blank lines
# ---------------------------------------------------------------------------
@test "config file ignores comments and blank lines" {
  printf '# This is a comment\n\nnavigation\n\n# Another comment\n' > "$TEST_HOME/.dotfiles-data/enabled-groups"
  run init_run 'typeset -f gp >/dev/null && echo "gp_ok"'
  [ "$status" -eq 0 ]
  [ "$output" = "gp_ok" ]
}

@test "config with comments does not load unlisted groups" {
  printf '# This is a comment\nnavigation\n' > "$TEST_HOME/.dotfiles-data/enabled-groups"
  run init_run 'typeset -f gsync >/dev/null && echo "gsync_ok" || echo "gsync_missing"'
  [ "$status" -eq 0 ]
  [ "$output" = "gsync_missing" ]
}

# ---------------------------------------------------------------------------
# Group registry is populated
# ---------------------------------------------------------------------------
@test "group registry _DOTFILES_GROUPS is populated" {
  run init_run 'echo "${#_DOTFILES_GROUPS}"'
  [ "$status" -eq 0 ]
  [ "$output" -ge 5 ]
}

# ---------------------------------------------------------------------------
# PATH is not corrupted after sourcing
# ---------------------------------------------------------------------------
@test "PATH is not corrupted after sourcing init.sh" {
  run init_run 'echo "$PATH"'
  [ "$status" -eq 0 ]
  # PATH should still contain standard paths
  [[ "$output" == */usr/bin* ]]
}

# ---------------------------------------------------------------------------
# dotfiles-setup creates config file (text mode, no gum)
# ---------------------------------------------------------------------------
@test "dotfiles-setup creates enabled-groups config file" {
  # Run setup with input "1,2" in text mode (without gum in PATH)
  local nogum_path
  nogum_path=$(echo "$ORIG_PATH" | tr ':' '\n' | while read -r p; do
    [[ "$p" != */homebrew/bin ]] && printf '%s:' "$p"
  done | sed 's/:$//')

  run env HOME="$TEST_HOME" PATH="$nogum_path" /bin/zsh -c "echo '1,2' | source '$SETUP_SCRIPT'"
  [ -f "$TEST_HOME/.dotfiles-data/enabled-groups" ]
}

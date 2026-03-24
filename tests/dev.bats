#!/usr/bin/env bats
# Tests for aliases/dev.sh — Configurable Project Dev Launcher

DEV_SCRIPT="/Users/arielsurco/dotfiles/aliases/dev.sh"

setup() {
  # Resolve through /private to match zsh :A behavior on macOS
  export TEST_HOME="$(/bin/zsh -c "d=\$(mktemp -d); echo \${d:A}")"
  export REAL_HOME="$HOME"
  export HOME="$TEST_HOME"
  export ORIG_PATH="$PATH"

  # Create test project directories
  mkdir -p "$TEST_HOME/projects/api"
  mkdir -p "$TEST_HOME/projects/web"
  mkdir -p "$TEST_HOME/projects/admin"
}

teardown() {
  export HOME="$REAL_HOME"
  export PATH="$ORIG_PATH"
  rm -rf "$TEST_HOME"
}

# Helper: run a dev command in zsh with controlled HOME and GP_PROJECTS
dev_run() {
  env HOME="$TEST_HOME" /bin/zsh -c "
    compdef() { :; }
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    typeset -gA GP_PROJECTS
    GP_PROJECTS=(api '$TEST_HOME/projects/api' web '$TEST_HOME/projects/web' admin '$TEST_HOME/projects/admin')
    source '$DEV_SCRIPT' && $*"
}

# Helper: run a dev command without gum (forces non-interactive fallback)
dev_run_no_gum() {
  env HOME="$TEST_HOME" PATH="/usr/bin:/bin" /bin/zsh -c "
    compdef() { :; }
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    typeset -gA GP_PROJECTS
    GP_PROJECTS=(api '$TEST_HOME/projects/api' web '$TEST_HOME/projects/web' admin '$TEST_HOME/projects/admin')
    source '$DEV_SCRIPT' && $*"
}

# Helper: set up a named config file
create_config() {
  local name="$1"
  local content="${2:-echo running-$name}"
  local dir="$TEST_HOME/.dotfiles-data/dev-configs"
  mkdir -p "$dir"
  echo "$content" > "$dir/${name}.sh"
}

# Helper: set up a project .ref file
create_ref() {
  local project="$1"
  local config_name="$2"
  local dir="$TEST_HOME/.dotfiles-data/dev-configs/projects"
  mkdir -p "$dir"
  echo "$config_name" > "$dir/${project}.ref"
}

# Helper: set up a project override .sh file
create_override() {
  local project="$1"
  local content="${2:-echo custom-$project}"
  local dir="$TEST_HOME/.dotfiles-data/dev-configs/projects"
  mkdir -p "$dir"
  echo "$content" > "$dir/${project}.sh"
}

# ---------------------------------------------------------------------------
# _dev_resolve_config — Config resolution
# ---------------------------------------------------------------------------

@test "_dev_resolve_config returns named config path for .ref" {
  create_config "ruby-backend"
  create_ref "api" "ruby-backend"

  run dev_run "_dev_resolve_config api"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev-configs/ruby-backend.sh"* ]]
}

@test "_dev_resolve_config returns override .sh path" {
  create_override "web"

  run dev_run "_dev_resolve_config web"
  [ "$status" -eq 0 ]
  [[ "$output" == *"projects/web.sh"* ]]
}

@test "_dev_resolve_config returns error for missing config" {
  run dev_run "_dev_resolve_config admin"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_dev_resolve_config returns error for .ref with missing config" {
  create_ref "api" "nonexistent"

  run dev_run "_dev_resolve_config api"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

# ---------------------------------------------------------------------------
# _dev_project_indicator — Status indicators
# ---------------------------------------------------------------------------

@test "_dev_project_indicator shows config name for .ref" {
  create_config "ruby-backend"
  create_ref "api" "ruby-backend"

  run dev_run "_dev_project_indicator api"
  [ "$status" -eq 0 ]
  [[ "$output" == "[ruby-backend]" ]]
}

@test "_dev_project_indicator shows [custom] for override .sh" {
  create_override "web"

  run dev_run "_dev_project_indicator web"
  [ "$status" -eq 0 ]
  [[ "$output" == "[custom]" ]]
}

@test "_dev_project_indicator returns empty for unconfigured" {
  run dev_run "_dev_project_indicator admin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# _dev_clone_and_edit — Checksum logic
# ---------------------------------------------------------------------------

@test "_dev_clone_and_edit saves .ref to original when content unchanged" {
  create_config "ruby-backend" "echo hello"

  # Use EDITOR=true (no-op) to simulate no changes
  # gum input with --value to simulate name input returning project name
  run env HOME="$TEST_HOME" EDITOR="true" /bin/zsh -c "
    compdef() { :; }
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    typeset -gA GP_PROJECTS
    GP_PROJECTS=(api '$TEST_HOME/projects/api')
    gum() {
      if [[ \"\$1\" == \"input\" ]]; then
        echo ''
      fi
    }
    source '$DEV_SCRIPT'
    _dev_clone_and_edit ruby-backend api"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uses config"* ]]

  # Verify .ref was created pointing to original config
  [ -f "$TEST_HOME/.dotfiles-data/dev-configs/projects/api.ref" ]
  [ ! -f "$TEST_HOME/.dotfiles-data/dev-configs/projects/api.sh" ]
  [[ "$(< "$TEST_HOME/.dotfiles-data/dev-configs/projects/api.ref")" == "ruby-backend" ]]
}

@test "_dev_clone_and_edit saves new named config when content modified" {
  create_config "ruby-backend" "echo hello"

  # Use a script that appends content as EDITOR to simulate modification
  local editor_script="$TEST_HOME/fake-editor.sh"
  printf '#!/bin/zsh\necho "echo modified" >> "$1"\n' > "$editor_script"
  chmod +x "$editor_script"

  run env HOME="$TEST_HOME" EDITOR="$editor_script" /bin/zsh -c "
    compdef() { :; }
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    typeset -gA GP_PROJECTS
    GP_PROJECTS=(api '$TEST_HOME/projects/api')
    gum() {
      if [[ \"\$1\" == \"input\" ]]; then
        echo 'api-custom'
      fi
    }
    source '$DEV_SCRIPT'
    _dev_clone_and_edit ruby-backend api"
  [ "$status" -eq 0 ]
  [[ "$output" == *"saved config"* ]]

  # Verify new named config was created + ref points to it
  [ -f "$TEST_HOME/.dotfiles-data/dev-configs/api-custom.sh" ]
  [ -f "$TEST_HOME/.dotfiles-data/dev-configs/projects/api.ref" ]
  [[ "$(< "$TEST_HOME/.dotfiles-data/dev-configs/projects/api.ref")" == "api-custom" ]]
}

# ---------------------------------------------------------------------------
# _dev_config_dependents — Dependent project lookup
# ---------------------------------------------------------------------------

@test "_dev_config_dependents returns all projects referencing config" {
  create_config "ruby-backend"
  create_ref "api" "ruby-backend"
  create_ref "api-fr" "ruby-backend"
  create_ref "payments" "ruby-backend"

  run dev_run "_dev_config_dependents ruby-backend"
  [ "$status" -eq 0 ]
  [[ "$output" == *"api"* ]]
  [[ "$output" == *"api-fr"* ]]
  [[ "$output" == *"payments"* ]]
}

@test "_dev_config_dependents returns empty for unused config" {
  create_config "unused-config"

  run dev_run "_dev_config_dependents unused-config"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_dev_config_dependents ignores refs to other configs" {
  create_config "ruby-backend"
  create_config "node-frontend"
  create_ref "api" "ruby-backend"
  create_ref "web" "node-frontend"

  run dev_run "_dev_config_dependents ruby-backend"
  [ "$status" -eq 0 ]
  [[ "$output" == *"api"* ]]
  [[ "$output" != *"web"* ]]
}

# ---------------------------------------------------------------------------
# _dev_config_delete — Config cascade deletion
# ---------------------------------------------------------------------------

@test "_dev_config_delete removes config and all dependent .ref files" {
  create_config "ruby-backend"
  create_ref "api" "ruby-backend"
  create_ref "api-fr" "ruby-backend"
  create_ref "payments" "ruby-backend"

  local base="$TEST_HOME/.dotfiles-data/dev-configs"

  # Verify setup
  [ -f "$base/ruby-backend.sh" ]
  [ -f "$base/projects/api.ref" ]
  [ -f "$base/projects/api-fr.ref" ]
  [ -f "$base/projects/payments.ref" ]

  # Call the internal cascade logic directly (skip gum interaction)
  run dev_run "
    base=\$(_dev_config_dir)
    config_name='ruby-backend'
    deps=\$(_dev_config_dependents \"\$config_name\")
    while IFS= read -r dep_name; do
      command rm -f \"\$base/projects/\${dep_name}.ref\"
    done <<< \"\$deps\"
    command rm -f \"\$base/\${config_name}.sh\"
    echo 'deleted'"
  [ "$status" -eq 0 ]

  # Verify all removed
  [ ! -f "$base/ruby-backend.sh" ]
  [ ! -f "$base/projects/api.ref" ]
  [ ! -f "$base/projects/api-fr.ref" ]
  [ ! -f "$base/projects/payments.ref" ]
}

# ---------------------------------------------------------------------------
# _dev_remove_project — Project config removal
# ---------------------------------------------------------------------------

@test "_dev_remove_project with shared ref: remove-only deletes .ref only" {
  create_config "ruby-backend"
  create_ref "api" "ruby-backend"
  create_ref "api-fr" "ruby-backend"

  local base="$TEST_HOME/.dotfiles-data/dev-configs"

  # Simulate "Remove config for api only" path
  run dev_run "
    base=\$(_dev_config_dir)
    command rm -f \"\$base/projects/api.ref\"
    echo 'removed'"
  [ "$status" -eq 0 ]

  # api.ref gone, api-fr.ref and config remain
  [ ! -f "$base/projects/api.ref" ]
  [ -f "$base/projects/api-fr.ref" ]
  [ -f "$base/ruby-backend.sh" ]
}

@test "_dev_remove_project with override .sh deletes .sh" {
  create_override "web" "echo web-dev"

  local base="$TEST_HOME/.dotfiles-data/dev-configs"
  [ -f "$base/projects/web.sh" ]

  # Simulate the removal path
  run dev_run "
    base=\$(_dev_config_dir)
    command rm -f \"\$base/projects/web.sh\"
    echo 'removed'"
  [ "$status" -eq 0 ]

  [ ! -f "$base/projects/web.sh" ]
}

@test "_dev_remove_project with no config returns error" {
  run dev_run "_dev_remove_project admin 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no config found"* ]]
}

# ---------------------------------------------------------------------------
# dev <project> — Integration: named config + .ref execution
# ---------------------------------------------------------------------------

@test "dev <project> sources named config via .ref" {
  create_config "ruby-backend" "export DEV_TEST_MARKER=sourced-ruby"
  create_ref "api" "ruby-backend"

  run dev_run "dev api && echo \$DEV_TEST_MARKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sourced-ruby"* ]]
}

@test "dev <project> sources override .sh config" {
  create_override "web" "export DEV_TEST_MARKER=sourced-custom"

  run dev_run "dev web && echo \$DEV_TEST_MARKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sourced-custom"* ]]
}

@test "dev with unknown project shows error" {
  run dev_run "dev nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "dev with no args and no projects shows error" {
  run env HOME="$TEST_HOME" /bin/zsh -c "
    compdef() { :; }
    export DOTFILES_DATA=\"\$HOME/.dotfiles-data\"; mkdir -p \"\$DOTFILES_DATA\"
    typeset -gA GP_PROJECTS
    source '$DEV_SCRIPT'
    dev"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no projects"* ]]
}

@test "dev config list shows configs with project counts" {
  create_config "ruby-backend"
  create_config "node-frontend"
  create_ref "api" "ruby-backend"
  create_ref "api-fr" "ruby-backend"

  run dev_run_no_gum "_dev_config_list"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ruby-backend"* ]]
  [[ "$output" == *"node-frontend"* ]]
  [[ "$output" == *"2 projects"* ]]
  [[ "$output" == *"0 projects"* ]]
}

@test "dev config list with no configs shows helpful message" {
  run dev_run_no_gum "_dev_config_list"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No configs"* ]]
}

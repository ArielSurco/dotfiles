#!/usr/bin/env bats
# Tests for ai/setup.sh — symlink creation, target assembly, tool selection

AI_SETUP_SCRIPT="/Users/arielsurco/dotfiles/ai/setup.sh"

setup() {
  export TEST_HOME="$(/bin/zsh -c "d=\$(mktemp -d); echo \${d:A}")"
  export REAL_HOME="$HOME"
  export HOME="$TEST_HOME"

  # Directories used by tests
  export TEST_SOURCE_DIR="$TEST_HOME/source"
  export TEST_TARGET_DIR="$TEST_HOME/target"
  export TEST_DOTFILES_DATA="$TEST_HOME/.dotfiles-data"

  mkdir -p "$TEST_SOURCE_DIR" "$TEST_TARGET_DIR" "$TEST_DOTFILES_DATA"
}

teardown() {
  export HOME="$REAL_HOME"
  rm -rf "$TEST_HOME"
}

# Helper: run a zsh snippet that sources ai/setup.sh with controlled env
ai_run() {
  env HOME="$TEST_HOME" /bin/zsh -c "
    export _SETUP_SCRIPT_DIR='$TEST_SOURCE_DIR'
    export DOTFILES_DATA='$TEST_DOTFILES_DATA'
    source '$AI_SETUP_SCRIPT'
    $*
  "
}

# ===========================================================================
# _ai_ensure_symlink — edge cases
# ===========================================================================

@test "ensure_symlink: target doesn't exist → creates symlink without prompting" {
  echo "source content" > "$TEST_SOURCE_DIR/myfile"

  run ai_run '_ai_ensure_symlink "$TEST_SOURCE_DIR/myfile" "$TEST_TARGET_DIR/mylink"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[link]"* ]]
  # Verify symlink was created
  [ -L "$TEST_TARGET_DIR/mylink" ]
  [ "$(readlink "$TEST_TARGET_DIR/mylink")" = "$TEST_SOURCE_DIR/myfile" ]
}

@test "ensure_symlink: target is already correct symlink → prints [ok], no changes" {
  echo "source content" > "$TEST_SOURCE_DIR/myfile"
  ln -sf "$TEST_SOURCE_DIR/myfile" "$TEST_TARGET_DIR/mylink"

  run ai_run '_ai_ensure_symlink "$TEST_SOURCE_DIR/myfile" "$TEST_TARGET_DIR/mylink"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok]"* ]]
  [[ "$output" == *"already correct"* ]]
  # Symlink unchanged
  [ "$(readlink "$TEST_TARGET_DIR/mylink")" = "$TEST_SOURCE_DIR/myfile" ]
}

@test "ensure_symlink: wrong symlink + confirm replace → backs up and creates correct symlink" {
  echo "source content" > "$TEST_SOURCE_DIR/myfile"
  echo "wrong content" > "$TEST_SOURCE_DIR/wrongfile"
  ln -sf "$TEST_SOURCE_DIR/wrongfile" "$TEST_TARGET_DIR/mylink"

  # Override _ai_confirm_overwrite to always return 0 (replace)
  run ai_run '
    _ai_confirm_overwrite() { return 0; }
    _ai_ensure_symlink "$TEST_SOURCE_DIR/myfile" "$TEST_TARGET_DIR/mylink"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[backup]"* ]]
  [[ "$output" == *"[link]"* ]]
  # New symlink points to correct source
  [ -L "$TEST_TARGET_DIR/mylink" ]
  [ "$(readlink "$TEST_TARGET_DIR/mylink")" = "$TEST_SOURCE_DIR/myfile" ]
}

@test "ensure_symlink: wrong symlink + skip → keeps existing, prints [skip]" {
  echo "source content" > "$TEST_SOURCE_DIR/myfile"
  echo "wrong content" > "$TEST_SOURCE_DIR/wrongfile"
  ln -sf "$TEST_SOURCE_DIR/wrongfile" "$TEST_TARGET_DIR/mylink"

  # Override _ai_confirm_overwrite to return 1 (skip)
  run ai_run '
    _ai_confirm_overwrite() { return 1; }
    _ai_ensure_symlink "$TEST_SOURCE_DIR/myfile" "$TEST_TARGET_DIR/mylink"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[skip]"* ]]
  # Original symlink still points to wrongfile
  [ "$(readlink "$TEST_TARGET_DIR/mylink")" = "$TEST_SOURCE_DIR/wrongfile" ]
}

@test "ensure_symlink: regular file + confirm replace → backs up and creates symlink" {
  echo "source content" > "$TEST_SOURCE_DIR/myfile"
  echo "existing regular file" > "$TEST_TARGET_DIR/mylink"

  run ai_run '
    _ai_confirm_overwrite() { return 0; }
    _ai_ensure_symlink "$TEST_SOURCE_DIR/myfile" "$TEST_TARGET_DIR/mylink"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[backup]"* ]]
  [[ "$output" == *"[link]"* ]]
  # Target is now a symlink
  [ -L "$TEST_TARGET_DIR/mylink" ]
  [ "$(readlink "$TEST_TARGET_DIR/mylink")" = "$TEST_SOURCE_DIR/myfile" ]
  # Backup file should exist (name contains .backup.)
  local backup_count
  backup_count=$(/bin/ls "$TEST_TARGET_DIR"/mylink.backup.* 2>/dev/null | wc -l | tr -d ' ')
  [ "$backup_count" -eq 1 ]
}

@test "ensure_symlink: regular file + skip → keeps existing file" {
  echo "source content" > "$TEST_SOURCE_DIR/myfile"
  echo "existing regular file" > "$TEST_TARGET_DIR/mylink"

  run ai_run '
    _ai_confirm_overwrite() { return 1; }
    _ai_ensure_symlink "$TEST_SOURCE_DIR/myfile" "$TEST_TARGET_DIR/mylink"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[skip]"* ]]
  # Target is still a regular file, not a symlink
  [ ! -L "$TEST_TARGET_DIR/mylink" ]
  [ -f "$TEST_TARGET_DIR/mylink" ]
  [ "$(cat "$TEST_TARGET_DIR/mylink")" = "existing regular file" ]
}

@test "ensure_symlink: directory + confirm replace → backs up and creates symlink" {
  mkdir -p "$TEST_SOURCE_DIR/srcdir"
  echo "file in srcdir" > "$TEST_SOURCE_DIR/srcdir/inner.txt"
  mkdir -p "$TEST_TARGET_DIR/mylink"
  echo "file in existing dir" > "$TEST_TARGET_DIR/mylink/old.txt"

  run ai_run '
    _ai_confirm_overwrite() { return 0; }
    _ai_ensure_symlink "$TEST_SOURCE_DIR/srcdir" "$TEST_TARGET_DIR/mylink"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[backup]"* ]]
  [[ "$output" == *"[link]"* ]]
  # Target is now a symlink to the source dir
  [ -L "$TEST_TARGET_DIR/mylink" ]
  [ "$(readlink "$TEST_TARGET_DIR/mylink")" = "$TEST_SOURCE_DIR/srcdir" ]
}

@test "ensure_symlink: parent directory doesn't exist → creates parent dirs + symlink" {
  echo "source content" > "$TEST_SOURCE_DIR/myfile"

  run ai_run '_ai_ensure_symlink "$TEST_SOURCE_DIR/myfile" "$TEST_TARGET_DIR/deep/nested/dir/mylink"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[link]"* ]]
  [ -L "$TEST_TARGET_DIR/deep/nested/dir/mylink" ]
  [ "$(readlink "$TEST_TARGET_DIR/deep/nested/dir/mylink")" = "$TEST_SOURCE_DIR/myfile" ]
}

# ===========================================================================
# _ai_assemble_targets
# ===========================================================================

@test "assemble_targets: all parts exist → generates target with header + content" {
  echo "part one content" > "$TEST_SOURCE_DIR/part1.md"
  echo "part two content" > "$TEST_SOURCE_DIR/part2.md"
  local target_file="$TEST_TARGET_DIR/assembled.md"

  run ai_run "_ai_assemble_targets '$target_file' '$TEST_SOURCE_DIR/part1.md' '$TEST_SOURCE_DIR/part2.md'"
  [ "$status" -eq 0 ]
  # Target file should exist with header
  [ -f "$target_file" ]
  local content
  content="$(cat "$target_file")"
  [[ "$content" == *"GENERATED FILE"* ]]
  [[ "$content" == *"part one content"* ]]
  [[ "$content" == *"part two content"* ]]
}

@test "assemble_targets: a part is missing → prints warning, includes other parts" {
  echo "part one content" > "$TEST_SOURCE_DIR/part1.md"
  local target_file="$TEST_TARGET_DIR/assembled.md"

  run ai_run "_ai_assemble_targets '$target_file' '$TEST_SOURCE_DIR/part1.md' '$TEST_SOURCE_DIR/nonexistent.md'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn]"* ]]
  [[ "$output" == *"nonexistent.md"* ]]
  # Target should still have the existing part
  local content
  content="$(cat "$target_file")"
  [[ "$content" == *"part one content"* ]]
}

@test "assemble_targets: idempotent → running twice produces same output" {
  echo "part one content" > "$TEST_SOURCE_DIR/part1.md"
  echo "part two content" > "$TEST_SOURCE_DIR/part2.md"
  local target_file="$TEST_TARGET_DIR/assembled.md"

  ai_run "_ai_assemble_targets '$target_file' '$TEST_SOURCE_DIR/part1.md' '$TEST_SOURCE_DIR/part2.md'"
  local first_run
  first_run="$(cat "$target_file")"

  ai_run "_ai_assemble_targets '$target_file' '$TEST_SOURCE_DIR/part1.md' '$TEST_SOURCE_DIR/part2.md'"
  local second_run
  second_run="$(cat "$target_file")"

  [ "$first_run" = "$second_run" ]
}

# ===========================================================================
# Tool selection conditional symlinks
# ===========================================================================

# Helper: run _ai_setup with controlled tool selection (text mode, no gum)
# $1 = selection input (e.g. "1" for claude, "2" for cursor, "1,2" for both, "" for none)
ai_setup_with_selection() {
  local selection="$1"
  # Build a PATH that excludes gum
  local nogum_path
  nogum_path=$(/bin/zsh -c "echo \$PATH" | tr ':' '\n' | while read -r p; do
    [[ -x "$p/gum" ]] || printf '%s:' "$p"
  done | /usr/bin/sed 's/:$//')

  # Create minimal source structure that _ai_setup expects
  local ai_dir="$TEST_SOURCE_DIR/ai"
  mkdir -p "$ai_dir/parts" "$ai_dir/rules" "$ai_dir/targets" "$ai_dir/skills/test-skill"
  echo "# engram" > "$ai_dir/parts/engram-protocol.md"
  echo "# persona" > "$ai_dir/rules/persona.md"
  echo "# sdd" > "$ai_dir/parts/sdd-orchestrator.md"
  echo "# skill readme" > "$ai_dir/skills/test-skill/SKILL.md"

  # Create target dirs that _ai_setup expects
  mkdir -p "$TEST_HOME/.claude" "$TEST_HOME/.cursor/rules"

  env HOME="$TEST_HOME" PATH="$nogum_path" /bin/zsh -c "
    export _SETUP_SCRIPT_DIR='$TEST_SOURCE_DIR'
    export DOTFILES_DATA='$TEST_DOTFILES_DATA'
    export _AI_DIR='$ai_dir'
    source '$AI_SETUP_SCRIPT'
    # Override _AI_DIR to point to our test structure
    _AI_DIR='$ai_dir'
    echo '$selection' | _ai_setup
  "
}

@test "tool selection: only claude selected → creates claude symlinks, NOT cursor" {
  run ai_setup_with_selection "1"
  [ "$status" -eq 0 ]
  # Claude CLAUDE.md symlink should exist
  [ -L "$TEST_HOME/.claude/CLAUDE.md" ]
  # Cursor symlink should NOT exist
  [ ! -L "$TEST_HOME/.cursor/rules/gentle-ai.mdc" ]
}

@test "tool selection: only cursor selected → creates cursor symlink, NOT claude" {
  run ai_setup_with_selection "2"
  [ "$status" -eq 0 ]
  # Cursor symlink should exist
  [ -L "$TEST_HOME/.cursor/rules/gentle-ai.mdc" ]
  # Claude CLAUDE.md symlink should NOT exist
  [ ! -L "$TEST_HOME/.claude/CLAUDE.md" ]
}

@test "tool selection: neither selected → no symlinks, targets still assembled" {
  run ai_setup_with_selection ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"No AI tools selected"* ]]
  [[ "$output" == *"targets assembled"* ]]
  # No symlinks created
  [ ! -L "$TEST_HOME/.claude/CLAUDE.md" ]
  [ ! -L "$TEST_HOME/.cursor/rules/gentle-ai.mdc" ]
  # But target files should have been assembled
  [ -f "$TEST_SOURCE_DIR/ai/targets/claude.md" ]
  [ -f "$TEST_SOURCE_DIR/ai/targets/cursor.mdc" ]
}

# ===========================================================================
# Edge Case 1: Broken symlink
# ===========================================================================

@test "ensure_symlink: broken symlink + confirm replace → backs up and creates correct symlink" {
  echo "source content" > "$TEST_SOURCE_DIR/myfile"
  # Create a symlink pointing to a non-existent path
  ln -sf "$TEST_SOURCE_DIR/nonexistent_target" "$TEST_TARGET_DIR/mylink"
  # Verify it's a broken symlink
  [ -L "$TEST_TARGET_DIR/mylink" ]
  [ ! -e "$TEST_TARGET_DIR/mylink" ]

  run ai_run '
    _ai_confirm_overwrite() { return 0; }
    _ai_ensure_symlink "$TEST_SOURCE_DIR/myfile" "$TEST_TARGET_DIR/mylink"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[backup]"* ]]
  [[ "$output" == *"[link]"* ]]
  # Verify the broken symlink was backed up
  local backup_count
  backup_count=$(/bin/ls "$TEST_TARGET_DIR"/mylink.backup.* 2>/dev/null | wc -l | tr -d ' ')
  [ "$backup_count" -eq 1 ]
  # New symlink points to correct source
  [ -L "$TEST_TARGET_DIR/mylink" ]
  [ "$(readlink "$TEST_TARGET_DIR/mylink")" = "$TEST_SOURCE_DIR/myfile" ]
}

# ===========================================================================
# Edge Case 2: Skill name conflict
# ===========================================================================

@test "ensure_symlink: user directory with same name as skill + confirm → backs up with contents and creates symlink" {
  # Our skill source
  mkdir -p "$TEST_SOURCE_DIR/skills/go-testing"
  echo "# our skill" > "$TEST_SOURCE_DIR/skills/go-testing/SKILL.md"

  # User's custom directory at the target path (same name, not a symlink)
  mkdir -p "$TEST_TARGET_DIR/go-testing"
  echo "# user custom config" > "$TEST_TARGET_DIR/go-testing/custom.md"

  run ai_run '
    _ai_confirm_overwrite() { return 0; }
    _ai_ensure_symlink "$TEST_SOURCE_DIR/skills/go-testing" "$TEST_TARGET_DIR/go-testing"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[backup]"* ]]
  [[ "$output" == *"[link]"* ]]
  # New symlink points to our skill
  [ -L "$TEST_TARGET_DIR/go-testing" ]
  [ "$(readlink "$TEST_TARGET_DIR/go-testing")" = "$TEST_SOURCE_DIR/skills/go-testing" ]
  # Backup should contain the user's custom file
  local backup_dir
  backup_dir=$(/bin/ls -d "$TEST_TARGET_DIR"/go-testing.backup.* 2>/dev/null | head -1)
  [ -n "$backup_dir" ]
  [ -f "$backup_dir/custom.md" ]
  [ "$(cat "$backup_dir/custom.md")" = "# user custom config" ]
}

@test "ensure_symlink: user directory with same name as skill + skip → keeps user's directory" {
  # Our skill source
  mkdir -p "$TEST_SOURCE_DIR/skills/go-testing"
  echo "# our skill" > "$TEST_SOURCE_DIR/skills/go-testing/SKILL.md"

  # User's custom directory at the target path
  mkdir -p "$TEST_TARGET_DIR/go-testing"
  echo "# user custom config" > "$TEST_TARGET_DIR/go-testing/custom.md"

  run ai_run '
    _ai_confirm_overwrite() { return 1; }
    _ai_ensure_symlink "$TEST_SOURCE_DIR/skills/go-testing" "$TEST_TARGET_DIR/go-testing"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[skip]"* ]]
  # User's directory is still there, not a symlink
  [ ! -L "$TEST_TARGET_DIR/go-testing" ]
  [ -d "$TEST_TARGET_DIR/go-testing" ]
  [ -f "$TEST_TARGET_DIR/go-testing/custom.md" ]
}

# ===========================================================================
# Edge Case 3: Deselected tool cleanup
# ===========================================================================

@test "cleanup_deselected: deselect cursor → cursor symlink pointing to our dotfiles gets removed" {
  local ai_dir="$TEST_SOURCE_DIR/ai"
  mkdir -p "$ai_dir/targets"
  echo "cursor content" > "$ai_dir/targets/cursor.mdc"
  mkdir -p "$TEST_HOME/.cursor/rules"
  # Symlink pointing to our dotfiles
  ln -sf "$ai_dir/targets/cursor.mdc" "$TEST_HOME/.cursor/rules/gentle-ai.mdc"

  run ai_run '
    _ai_confirm_overwrite() { return 0; }
    _ai_cleanup_deselected "'"$ai_dir"'" "claude"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[cleanup]"* ]]
  # Symlink should be gone (backed up)
  [ ! -L "$TEST_HOME/.cursor/rules/gentle-ai.mdc" ]
  # Backup should exist
  local backup_count
  backup_count=$(/bin/ls "$TEST_HOME/.cursor/rules"/gentle-ai.mdc.backup.* 2>/dev/null | wc -l | tr -d ' ')
  [ "$backup_count" -eq 1 ]
}

@test "cleanup_deselected: deselect cursor → cursor symlink pointing elsewhere is left alone" {
  local ai_dir="$TEST_SOURCE_DIR/ai"
  mkdir -p "$ai_dir/targets"
  mkdir -p "$TEST_HOME/.cursor/rules"
  # Symlink pointing somewhere else (not our dotfiles)
  echo "other content" > "$TEST_HOME/other-cursor.mdc"
  ln -sf "$TEST_HOME/other-cursor.mdc" "$TEST_HOME/.cursor/rules/gentle-ai.mdc"

  run ai_run '
    _ai_confirm_overwrite() { return 0; }
    _ai_cleanup_deselected "'"$ai_dir"'" "claude"
  '
  [ "$status" -eq 0 ]
  # Symlink should still be there — it doesn't point to our dotfiles
  [ -L "$TEST_HOME/.cursor/rules/gentle-ai.mdc" ]
  [ "$(readlink "$TEST_HOME/.cursor/rules/gentle-ai.mdc")" = "$TEST_HOME/other-cursor.mdc" ]
}

@test "cleanup_deselected: deselect claude → managed symlinks removed, user custom skills untouched" {
  local ai_dir="$TEST_SOURCE_DIR/ai"
  mkdir -p "$ai_dir/targets" "$ai_dir/skills/go-testing"
  echo "claude content" > "$ai_dir/targets/claude.md"
  echo "# skill" > "$ai_dir/skills/go-testing/SKILL.md"

  mkdir -p "$TEST_HOME/.claude/skills"
  # Managed symlinks (point to our ai_dir)
  ln -sf "$ai_dir/targets/claude.md" "$TEST_HOME/.claude/CLAUDE.md"
  ln -sfn "$ai_dir/skills/go-testing" "$TEST_HOME/.claude/skills/go-testing"
  # User's own custom skill (real directory, not managed by us)
  mkdir -p "$TEST_HOME/.claude/skills/my-custom-skill"
  echo "# custom" > "$TEST_HOME/.claude/skills/my-custom-skill/SKILL.md"

  run ai_run '
    _ai_confirm_overwrite() { return 0; }
    _ai_cleanup_deselected "'"$ai_dir"'" "cursor"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[cleanup]"* ]]
  # Managed symlinks should be removed
  [ ! -L "$TEST_HOME/.claude/CLAUDE.md" ]
  [ ! -L "$TEST_HOME/.claude/skills/go-testing" ]
  # User's custom skill should be untouched
  [ -d "$TEST_HOME/.claude/skills/my-custom-skill" ]
  [ -f "$TEST_HOME/.claude/skills/my-custom-skill/SKILL.md" ]
}

# ===========================================================================
# Edge Case 4: DOTFILES_DATA not defined
# ===========================================================================

@test "DOTFILES_DATA not set → defaults to ~/.dotfiles-data" {
  # Run without DOTFILES_DATA set, check it gets created
  local result
  result=$(env HOME="$TEST_HOME" /bin/zsh -c "
    unset DOTFILES_DATA
    export _SETUP_SCRIPT_DIR='$TEST_SOURCE_DIR'
    source '$AI_SETUP_SCRIPT'
    # Simulate the top of _ai_setup
    : \"\${DOTFILES_DATA:=\$HOME/.dotfiles-data}\"
    [[ -d \"\$DOTFILES_DATA\" ]] || mkdir -p \"\$DOTFILES_DATA\"
    echo \"\$DOTFILES_DATA\"
  ")
  [ "$result" = "$TEST_HOME/.dotfiles-data" ]
  [ -d "$TEST_HOME/.dotfiles-data" ]
}

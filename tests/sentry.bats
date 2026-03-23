#!/usr/bin/env bats
# Tests for aliases/sentry.sh — Interactive Sentry Issue Search

SENTRY_SCRIPT="/Users/arielsurco/dotfiles/aliases/sentry.sh"

setup() {
  export TEST_HOME="$(/bin/zsh -c "d=\$(mktemp -d); echo \${d:A}")"
  export REAL_HOME="$HOME"
  export HOME="$TEST_HOME"
  export ORIG_PATH="$PATH"

  # Create mock binaries directory
  mkdir -p "$TEST_HOME/bin"

  # Create mock ~/.sentryclirc
  cat > "$TEST_HOME/.sentryclirc" << 'CFG'
[auth]
token=fake-token-123

[defaults]
url=https://sentry.example.com
org=fudo
CFG

  # Mock curl — dispatches based on URL in arguments
  cat > "$TEST_HOME/bin/curl" << 'MOCK'
#!/bin/bash
# Find the URL argument (last positional arg after flags)
url=""
for arg in "$@"; do
  case "$arg" in
    -*)  ;;
    *http*) url="$arg" ;;
  esac
done

if [[ "$url" == *"/projects/"*"/tags/"* ]]; then
  echo '[{"key":"fudo_pay.sn","name":"Fudo Pay.Sn"},{"key":"environment","name":"Environment"}]'
elif [[ "$url" == *"/projects/"* ]]; then
  echo '[{"slug":"payments-service","id":"1"},{"slug":"api","id":"2"},{"slug":"app-waiters","id":"3"}]'
elif [[ "$url" == *"/events/"* ]]; then
  echo '{"data":[{"id":"abc123","title":"Error in payment","timestamp":"2026-03-23T10:00:00","project":"payments-service","issue.id":"456"}]}'
else
  exit 1
fi
MOCK
  chmod +x "$TEST_HOME/bin/curl"

  # Mock gum — choose returns first line from stdin
  cat > "$TEST_HOME/bin/gum" << 'MOCK'
#!/bin/bash
if [[ "$1" == "choose" ]]; then
  head -1
fi
MOCK
  chmod +x "$TEST_HOME/bin/gum"

  # Mock jq — use real jq
  if command -v jq &>/dev/null; then
    ln -sf "$(command -v jq)" "$TEST_HOME/bin/jq"
  fi
}

teardown() {
  export HOME="$REAL_HOME"
  export PATH="$ORIG_PATH"
  rm -rf "$TEST_HOME"
}

# ---------------------------------------------------------------------------
# Entry point checks
# ---------------------------------------------------------------------------

@test "sentry without subcommand shows usage" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$ORIG_PATH" /bin/zsh -c "
    source '$SENTRY_SCRIPT'
    sentry
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: sentry search"* ]]
}

@test "sentry with unknown subcommand shows error" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$ORIG_PATH" /bin/zsh -c "
    source '$SENTRY_SCRIPT'
    sentry foobar
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
  [[ "$output" == *"Usage: sentry search"* ]]
}

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------

@test "sentry search without curl shows error" {
  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='/usr/bin:/bin'
    # Ensure curl is not available by using a clean path
    hash -r 2>/dev/null
    source '$SENTRY_SCRIPT'
    sentry search
  "
  # On macOS /usr/bin/curl exists, so we need a truly empty path
  # Use a path with only our mock dir but without curl
  mkdir -p "$TEST_HOME/nobin"
  cp "$TEST_HOME/bin/gum" "$TEST_HOME/nobin/gum"
  cp "$TEST_HOME/bin/jq" "$TEST_HOME/nobin/jq" 2>/dev/null || true

  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='$TEST_HOME/nobin'
    source '$SENTRY_SCRIPT'
    sentry search
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl not found"* ]]
}

@test "sentry search without jq shows error" {
  mkdir -p "$TEST_HOME/nobin"
  cp "$TEST_HOME/bin/curl" "$TEST_HOME/nobin/curl"
  cp "$TEST_HOME/bin/gum" "$TEST_HOME/nobin/gum"

  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='$TEST_HOME/nobin'
    source '$SENTRY_SCRIPT'
    sentry search
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is required"* ]]
}

@test "sentry search without gum shows error" {
  mkdir -p "$TEST_HOME/nobin"
  cp "$TEST_HOME/bin/curl" "$TEST_HOME/nobin/curl"
  ln -sf "$(command -v jq)" "$TEST_HOME/nobin/jq" 2>/dev/null || cp "$TEST_HOME/bin/jq" "$TEST_HOME/nobin/jq" 2>/dev/null || true

  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='$TEST_HOME/nobin'
    source '$SENTRY_SCRIPT'
    sentry search
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"gum is required"* ]]
}

@test "sentry search without .sentryclirc shows error" {
  rm -f "$TEST_HOME/.sentryclirc"

  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$ORIG_PATH" /bin/zsh -c "
    source '$SENTRY_SCRIPT'
    sentry search
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *".sentryclirc not found"* ]]
}

# ---------------------------------------------------------------------------
# Full flow with mocks
# ---------------------------------------------------------------------------

@test "sentry search full flow with SN tag detection" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$ORIG_PATH" /bin/zsh -c "
    source '$SENTRY_SCRIPT'
    echo 'SN12345' | sentry search
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fetching projects"* ]]
  [[ "$output" == *"Fetching tags"* ]]
  [[ "$output" == *"Serial Number"* ]]
  [[ "$output" == *"Searching events"* ]]
  [[ "$output" == *"Found 1 events"* ]]
  [[ "$output" == *"abc123"* ]]
  [[ "$output" == *"Error in payment"* ]]
}

# ---------------------------------------------------------------------------
# PATH safety
# ---------------------------------------------------------------------------

@test "PATH is not corrupted after sentry function" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$ORIG_PATH" /bin/zsh -c "
    source '$SENTRY_SCRIPT'
    sentry search >/dev/null 2>&1 <<< 'SN12345' || true
    command -v curl
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl"* ]]
}

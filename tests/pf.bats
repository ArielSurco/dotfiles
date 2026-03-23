#!/usr/bin/env bats
# Tests for aliases/pf.sh — Kubernetes Port Forwarding via HAProxy

PF_SCRIPT="/Users/arielsurco/dotfiles/aliases/pf.sh"

MOCK_DESCRIBE_OUTPUT='Name:                     haproxy
Namespace:                haproxy
Port:                     accounts-rw  5432/TCP
TargetPort:               5432/TCP
Port:                     payments-rw  5434/TCP
TargetPort:               5434/TCP'

setup() {
  export TEST_HOME="$(/bin/zsh -c "d=\$(mktemp -d); echo \${d:A}")"
  export REAL_HOME="$HOME"
  export HOME="$TEST_HOME"
  export ORIG_PATH="$PATH"

  # Create mock binaries directory and dotfiles-data
  mkdir -p "$TEST_HOME/bin"
  mkdir -p "$TEST_HOME/.dotfiles-data"

  # Mock kubectl
  cat > "$TEST_HOME/bin/kubectl" << MOCK
#!/bin/bash
if [[ "\$*" == *"get-contexts -o name"* ]]; then
  echo "sandbox"
  echo "staging"
elif [[ "\$*" == *"describe service haproxy"* ]]; then
  cat << 'DESC'
${MOCK_DESCRIBE_OUTPUT}
DESC
elif [[ "\$*" == *"port-forward"* ]]; then
  echo "MOCK_PF: \$*"
fi
MOCK
  chmod +x "$TEST_HOME/bin/kubectl"

  # Mock gum — choose returns first line from stdin
  cat > "$TEST_HOME/bin/gum" << 'MOCK'
#!/bin/bash
if [[ "$1" == "choose" ]]; then
  head -1
fi
MOCK
  chmod +x "$TEST_HOME/bin/gum"
}

teardown() {
  export HOME="$REAL_HOME"
  export PATH="$ORIG_PATH"
  rm -rf "$TEST_HOME"
}

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

@test "pf without kubectl shows error" {
  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='/usr/bin:/bin'
    export DOTFILES_DATA='$TEST_HOME/.dotfiles-data'
    source '$PF_SCRIPT'
    pf
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"kubectl not found"* ]]
}

@test "pf without gum shows error" {
  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='$TEST_HOME/bin:/usr/bin:/bin'
    export DOTFILES_DATA='$TEST_HOME/.dotfiles-data'
    rm -f '$TEST_HOME/bin/gum'
    source '$PF_SCRIPT'
    pf
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"gum is required"* ]]
}

@test "pf with too many args shows usage" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$ORIG_PATH" /bin/zsh -c "
    export DOTFILES_DATA='$TEST_HOME/.dotfiles-data'
    source '$PF_SCRIPT'
    pf ctx port extra
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: pf"* ]]
}

# ---------------------------------------------------------------------------
# Full flow with mocks
# ---------------------------------------------------------------------------

@test "pf full interactive flow with mocked kubectl and gum" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    export DOTFILES_DATA='$TEST_HOME/.dotfiles-data'
    source '$PF_SCRIPT'
    pf
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fetching ports from haproxy"* ]]
  [[ "$output" == *"Forwarding"* ]]
  [[ "$output" == *"MOCK_PF"* ]]
}

@test "pf with context arg skips context selection" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    export DOTFILES_DATA='$TEST_HOME/.dotfiles-data'
    source '$PF_SCRIPT'
    pf sandbox
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fetching ports from haproxy (sandbox)"* ]]
  [[ "$output" == *"MOCK_PF"* ]]
  [[ "$output" == *"--context=sandbox"* ]]
}

@test "pf with context and port-name connects directly" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    export DOTFILES_DATA='$TEST_HOME/.dotfiles-data'
    source '$PF_SCRIPT'
    pf sandbox payments-rw
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Forwarding sandbox"* ]]
  [[ "$output" == *"payments-rw"* ]]
  [[ "$output" == *"5434"* ]]
  [[ "$output" == *"MOCK_PF"* ]]
}

@test "pf with invalid port-name shows error" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    export DOTFILES_DATA='$TEST_HOME/.dotfiles-data'
    source '$PF_SCRIPT'
    pf sandbox nonexistent
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"port 'nonexistent' not found"* ]]
}

@test "pf caches ports after fetch" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    export DOTFILES_DATA='$TEST_HOME/.dotfiles-data'
    source '$PF_SCRIPT'
    pf sandbox payments-rw
    cat '$TEST_HOME/.dotfiles-data/pf-ports-sandbox'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"accounts-rw=5432"* ]]
  [[ "$output" == *"payments-rw=5434"* ]]
}

# ---------------------------------------------------------------------------
# PATH safety — regression test
# ---------------------------------------------------------------------------

@test "PATH is not corrupted after pf function" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$ORIG_PATH" /bin/zsh -c "
    export DOTFILES_DATA='$TEST_HOME/.dotfiles-data'
    source '$PF_SCRIPT'
    pf sandbox payments-rw >/dev/null 2>&1 || true
    command -v kubectl
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubectl"* ]]
}

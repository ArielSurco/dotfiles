#!/usr/bin/env bats
# Tests for aliases/pod.sh — Interactive Kubernetes Pod Connector

POD_SCRIPT="/Users/arielsurco/dotfiles/aliases/pod.sh"

setup() {
  export TEST_HOME="$(/bin/zsh -c "d=\$(mktemp -d); echo \${d:A}")"
  export REAL_HOME="$HOME"
  export HOME="$TEST_HOME"
  export ORIG_PATH="$PATH"

  # Create mock binaries directory
  mkdir -p "$TEST_HOME/bin"

  # Mock kubectl
  cat > "$TEST_HOME/bin/kubectl" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"get-contexts -o name"* ]]; then
  echo "sandbox"
  echo "staging"
  echo "production"
elif [[ "$*" == *"get pods"* ]]; then
  echo "payments-abc123"
  echo "payments-def456"
  echo "api-server-xyz789"
elif [[ "$*" == *"exec"* ]]; then
  echo "MOCK_EXEC: $*"
fi
MOCK
  chmod +x "$TEST_HOME/bin/kubectl"

  # Mock gum — choose returns first line from stdin, input returns test-namespace
  cat > "$TEST_HOME/bin/gum" << 'MOCK'
#!/bin/bash
if [[ "$1" == "choose" ]]; then
  head -1
elif [[ "$1" == "input" ]]; then
  echo "test-namespace"
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

@test "pod without kubectl shows error" {
  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='/usr/bin:/bin'
    source '$POD_SCRIPT'
    pod
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"kubectl not found"* ]]
}

@test "pod without gum shows error" {
  run env HOME="$TEST_HOME" /bin/zsh -c "
    export PATH='$TEST_HOME/bin:/usr/bin:/bin'
    rm -f '$TEST_HOME/bin/gum'
    source '$POD_SCRIPT'
    pod
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"gum not found"* ]]
}

@test "pod with too many args shows usage" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$ORIG_PATH" /bin/zsh -c "
    source '$POD_SCRIPT'
    pod ctx ns extra
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: pod"* ]]
}

# ---------------------------------------------------------------------------
# Full flow with mocks
# ---------------------------------------------------------------------------

@test "pod full interactive flow with mocked kubectl and gum" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    source '$POD_SCRIPT'
    echo 'test-ns' | pod
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Connecting to payments-abc123"* ]]
  [[ "$output" == *"MOCK_EXEC"* ]]
}

@test "pod with context arg skips context selection" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    source '$POD_SCRIPT'
    echo 'test-ns' | pod sandbox
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Connecting to payments-abc123"* ]]
  [[ "$output" == *"MOCK_EXEC"* ]]
  [[ "$output" == *"--context=sandbox"* ]]
}

@test "pod with context and namespace skips to pod selection" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    source '$POD_SCRIPT'
    pod staging kube-system
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Connecting to payments-abc123"* ]]
  [[ "$output" == *"--context=staging"* ]]
  [[ "$output" == *"-n kube-system"* ]]
}

# ---------------------------------------------------------------------------
# Error conditions
# ---------------------------------------------------------------------------

@test "pod shows error when no pods found" {
  # Override mock kubectl to return empty pod list
  cat > "$TEST_HOME/bin/kubectl" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"get-contexts -o name"* ]]; then
  echo "sandbox"
elif [[ "$*" == *"get pods"* ]]; then
  :
fi
MOCK
  chmod +x "$TEST_HOME/bin/kubectl"

  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    source '$POD_SCRIPT'
    pod sandbox test-ns
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"No pods found"* ]]
}

@test "pod shows error when kubectl get pods fails" {
  cat > "$TEST_HOME/bin/kubectl" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"get-contexts -o name"* ]]; then
  echo "sandbox"
elif [[ "$*" == *"get pods"* ]]; then
  exit 1
fi
MOCK
  chmod +x "$TEST_HOME/bin/kubectl"

  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    source '$POD_SCRIPT'
    pod sandbox test-ns
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to list pods"* ]]
}

# ---------------------------------------------------------------------------
# PATH safety — regression test
# ---------------------------------------------------------------------------

@test "PATH is not corrupted after pod function" {
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$ORIG_PATH" /bin/zsh -c "
    source '$POD_SCRIPT'
    pod sandbox test-namespace >/dev/null 2>&1 || true
    command -v kubectl
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubectl"* ]]
}

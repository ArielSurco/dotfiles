#!/usr/bin/env bats

setup() {
  TEST_HOME="$(mktemp -d)"
  TEST_HOME=$(cd "$TEST_HOME" && /bin/zsh -c 'echo ${PWD:A}')
  REAL_HOME="$HOME"
  REAL_PATH="$PATH"
  export HOME="$TEST_HOME"
  export INIT_SCRIPT="/Users/arielsurco/dotfiles/aliases/init.sh"

  # Create mock docker script directory
  mkdir -p "$TEST_HOME/bin"
}

teardown() {
  export HOME="$REAL_HOME"
  export PATH="$REAL_PATH"
  rm -rf "$TEST_HOME"
}

_create_mock_docker() {
  cat > "$TEST_HOME/bin/docker" <<'SCRIPT'
#!/bin/bash
case "$*" in
  "info") exit 0 ;;
  "ps -a --format {{.Names}}")
    echo "fudo-redis"
    echo "fudo-memcached"
    ;;
  ps\ -q\ -f\ name=*)
    if [[ "$*" == *"fudo-redis"* ]]; then
      echo "abc123"
    fi
    ;;
  start\ *)
    echo "started"
    ;;
esac
SCRIPT
  chmod +x "$TEST_HOME/bin/docker"
}

@test "dbs without docker shows error" {
  run env HOME="$TEST_HOME" PATH="/usr/bin:/bin" /bin/zsh -c "source '$INIT_SCRIPT' && dbs"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dbs: docker not found"* ]]
}

@test "dbs starts containers with mock docker" {
  _create_mock_docker
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "source '$INIT_SCRIPT' && dbs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fudo-memcached: started"* ]]
}

@test "dbs reports already running containers" {
  _create_mock_docker
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "source '$INIT_SCRIPT' && dbs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fudo-redis: running"* ]]
}

@test "dbs skips non-existent containers" {
  _create_mock_docker
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "source '$INIT_SCRIPT' && dbs"
  [ "$status" -eq 0 ]
  # fudo-database is in the containers array but not in mock docker ps -a output
  [[ "$output" != *"fudo-database:"* ]]
}

@test "PATH is not corrupted after dbs" {
  _create_mock_docker
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" /bin/zsh -c "
    source '$INIT_SCRIPT'
    BEFORE=\$PATH
    dbs
    [[ \$PATH == \$BEFORE ]]
  "
  [ "$status" -eq 0 ]
}

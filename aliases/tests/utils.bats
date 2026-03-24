#!/usr/bin/env bats

setup() {
  TEST_HOME="$(mktemp -d)"
  TEST_HOME=$(cd "$TEST_HOME" && /bin/zsh -c 'echo ${PWD:A}')
  REAL_HOME="$HOME"
  export HOME="$TEST_HOME"
  export INIT_SCRIPT="/Users/arielsurco/dotfiles/aliases/init.sh"
}

teardown() {
  export HOME="$REAL_HOME"
  rm -rf "$TEST_HOME"
}

@test "dotalias reloads aliases" {
  run env HOME="$TEST_HOME" /bin/zsh -c "source '$INIT_SCRIPT' && dotalias"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Aliases reloaded"* ]]
}

@test "dotalias makes GP_PROJECTS available" {
  run env HOME="$TEST_HOME" /bin/zsh -c "source '$INIT_SCRIPT' && dotalias && typeset -p GP_PROJECTS"
  [ "$status" -eq 0 ]
}

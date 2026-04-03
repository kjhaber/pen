#!/usr/bin/env bats
# Unit tests for claude-devcon script functions

setup() {
  source "${BATS_TEST_DIRNAME}/../claude-devcon"
}

@test "container_name: returns basename of current dir" {
  local tmpdir
  tmpdir=$(mktemp -d /tmp/devcon_test_XXXXX)
  cd "$tmpdir"
  run container_name
  [ "$status" -eq 0 ]
  [ "$output" = "$(basename "$tmpdir" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]_-' '-' | sed 's/-*$//')" ]
  cd /tmp
  rm -rf "$tmpdir"
}

@test "container_name: output contains only docker-safe characters" {
  local tmpdir
  tmpdir=$(mktemp -d /tmp/devcon_test_XXXXX)
  cd "$tmpdir"
  run container_name
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[a-z0-9_-]+$ ]]
  cd /tmp
  rm -rf "$tmpdir"
}

@test "container_name: output does not start with a hyphen" {
  local tmpdir
  tmpdir=$(mktemp -d /tmp/devcon_test_XXXXX)
  cd "$tmpdir"
  run container_name
  [ "$status" -eq 0 ]
  [[ "$output" != -* ]]
  cd /tmp
  rm -rf "$tmpdir"
}

@test "container_name: output does not end with a hyphen" {
  local tmpdir
  tmpdir=$(mktemp -d /tmp/devcon_test_XXXXX)
  cd "$tmpdir"
  run container_name
  [ "$status" -eq 0 ]
  [[ "$output" != *- ]]
  cd /tmp
  rm -rf "$tmpdir"
}

@test "container_name: worktree-style name preserves underscore separator" {
  local tmpdir
  tmpdir=$(mktemp -d /tmp/devcon_test_XXXXX)
  local wtdir="${tmpdir}/devcon_auth-refactor"
  mkdir -p "$wtdir"
  cd "$wtdir"
  run container_name
  [ "$status" -eq 0 ]
  [ "$output" = "devcon_auth-refactor" ]
  cd /tmp
  rm -rf "$tmpdir"
}

@test "script sources without errors" {
  # Verified by reaching this point; setup() sources the script
  true
}

#!/usr/bin/env bats
# Unit tests for claude-devcon script functions

setup() {
  MOCK_BIN=$(mktemp -d)
  export PATH="${MOCK_BIN}:${PATH}"
  source "${BATS_TEST_DIRNAME}/../claude-devcon"
}

teardown() {
  rm -rf "${MOCK_BIN:-}"
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

# ---------------------------------------------------------------------------
# _is_devcon_container
# ---------------------------------------------------------------------------

@test "_is_devcon_container: returns true for a known devcon container" {
  docker() {
    local args="$*"
    if [[ "$args" == *"name=^devcon-foo"* && "$args" == *"label=claude-devcon=true"* ]]; then
      echo "fakeid"
    fi
  }
  run _is_devcon_container "devcon-foo"
  [ "$status" -eq 0 ]
}

@test "_is_devcon_container: returns false for an unknown container" {
  docker() { true; }  # always returns empty
  run _is_devcon_container "not-a-devcon"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# cmd_stop with explicit container name
# ---------------------------------------------------------------------------

@test "cmd_stop: rejects a non-devcon container name with error" {
  docker() { true; }  # _is_devcon_container returns empty → not a devcon container
  run cmd_stop "not-a-devcon"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a claude-devcon container"* ]]
}

@test "cmd_stop: stops and removes a valid devcon container by name" {
  docker() {
    case "$1" in
      ps)
        # Both _is_devcon_container (with label filter) and existence check (without)
        # return a result for mycontainer
        if [[ "$*" == *"name=^mycontainer"* ]]; then
          echo "fakeid"
        fi ;;
      rm) ;;  # silent success
    esac
  }
  run cmd_stop "mycontainer"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Stopped and removed: mycontainer"* ]]
}

@test "cmd_stop: reports missing container for a valid devcon name that no longer exists" {
  docker() {
    case "$1" in
      ps)
        # _is_devcon_container passes (has label filter): container is known devcon
        if [[ "$*" == *"label=claude-devcon=true"* && "$*" == *"name=^gone-container"* ]]; then
          echo "fakeid"
        fi
        # Existence check without label filter: return empty (container gone)
        ;;
    esac
  }
  run cmd_stop "gone-container"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No container found"* ]]
}

# ---------------------------------------------------------------------------
# cmd_exec with explicit container name
# ---------------------------------------------------------------------------

@test "cmd_exec: rejects a non-devcon container name with error" {
  docker() { true; }
  run cmd_exec "not-a-devcon"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a claude-devcon container"* ]]
}

@test "cmd_exec: reports error when devcon container exists but is not running" {
  docker() {
    case "$1" in
      ps)
        # _is_devcon_container (with -aq and label filter): passes
        if [[ "$*" == *"label=claude-devcon=true"* && "$*" == *"name=^stopped-container"* ]]; then
          echo "fakeid"
        fi
        # Running check (with -q, no -a, no label filter): return empty
        ;;
    esac
  }
  run cmd_exec "stopped-container"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no running container"* ]]
}

# ---------------------------------------------------------------------------
# cmd_list --names-only
# ---------------------------------------------------------------------------

@test "cmd_list: --names-only outputs container names one per line" {
  docker() {
    if [[ "$*" == *"label=claude-devcon=true"* && "$*" == *"{{.Names}}"* ]]; then
      echo "devcon-foo"
      echo "devcon-bar"
    fi
  }
  run cmd_list "--names-only"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "devcon-foo" ]
  [ "${lines[1]}" = "devcon-bar" ]
}

@test "cmd_list: --names-only produces no table header" {
  docker() {
    if [[ "$*" == *"label=claude-devcon=true"* && "$*" == *"{{.Names}}"* ]]; then
      echo "devcon-foo"
    fi
  }
  run cmd_list "--names-only"
  [ "$status" -eq 0 ]
  [[ "$output" != *"NAMES"* ]]
}

# ---------------------------------------------------------------------------
# prompt / flag passthrough
# ---------------------------------------------------------------------------

# Helper: write a mock docker script that simulates a running container and
# echoes exec args so tests can inspect what claude would have been called with.
_mock_docker_running() {
  cat > "${MOCK_BIN}/docker" << 'EOF'
#!/usr/bin/env bash
case "$1" in
  ps)   echo "fakeid" ;;  # pretend container is already running
  exec) echo "$@" ;;      # echo exec args instead of actually exec-ing
esac
EOF
  chmod +x "${MOCK_BIN}/docker"
}

@test "cmd_launch: passes a prompt string through to claude" {
  _mock_docker_running
  run cmd_launch "fix the authentication bug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fix the authentication bug"* ]]
}

@test "cmd_launch: passes flags like --print through to claude" {
  _mock_docker_running
  run cmd_launch --print "what does this function do"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--print"* ]]
  [[ "$output" == *"what does this function do"* ]]
}

@test "cmd_launch: runs claude with no extra args when called with no arguments" {
  _mock_docker_running
  run cmd_launch
  [ "$status" -eq 0 ]
  # claude is invoked but no extra prompt/flags appended beyond --dangerously-skip-permissions
  [[ "$output" == *"claude --dangerously-skip-permissions"* ]]
  [[ "$output" != *"fix"* ]]
}

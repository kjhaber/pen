#!/usr/bin/env bats
# Unit tests for pen script functions

setup() {
  MOCK_BIN=$(mktemp -d)
  export PATH="${MOCK_BIN}:${PATH}"
  source "${BATS_TEST_DIRNAME}/../pen"
  # Set default harness so harness-dependent functions work without needing
  # configure_harness called explicitly in every test
  HARNESS=claude
  HARNESS_IMAGE="pen-claude:latest"
  HARNESS_CONFIG="${HOME}/.pen/claude"
  HARNESS_CONTAINER_CONFIG="/home/pen/.claude"
}

teardown() {
  rm -rf "${MOCK_BIN:-}"
}

@test "container_name: returns pen_ prefix plus sanitized basename" {
  local tmpdir
  tmpdir=$(mktemp -d /tmp/pen_test_XXXXX)
  cd "$tmpdir"
  run container_name
  [ "$status" -eq 0 ]
  local expected="pen_$(basename "$tmpdir" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]_-' '-' | sed 's/-*$//')"
  [ "$output" = "$expected" ]
  cd /tmp
  rm -rf "$tmpdir"
}

@test "container_name: output contains only docker-safe characters" {
  local tmpdir
  tmpdir=$(mktemp -d /tmp/pen_test_XXXXX)
  cd "$tmpdir"
  run container_name
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[a-z0-9_-]+$ ]]
  cd /tmp
  rm -rf "$tmpdir"
}

@test "container_name: output does not start with a hyphen" {
  local tmpdir
  tmpdir=$(mktemp -d /tmp/pen_test_XXXXX)
  cd "$tmpdir"
  run container_name
  [ "$status" -eq 0 ]
  [[ "$output" != -* ]]
  cd /tmp
  rm -rf "$tmpdir"
}

@test "container_name: output does not end with a hyphen" {
  local tmpdir
  tmpdir=$(mktemp -d /tmp/pen_test_XXXXX)
  cd "$tmpdir"
  run container_name
  [ "$status" -eq 0 ]
  [[ "$output" != *- ]]
  cd /tmp
  rm -rf "$tmpdir"
}

@test "container_name: worktree-style name preserves underscore separator" {
  local tmpdir
  tmpdir=$(mktemp -d /tmp/pen_test_XXXXX)
  local wtdir="${tmpdir}/myproject_auth-refactor"
  mkdir -p "$wtdir"
  cd "$wtdir"
  run container_name
  [ "$status" -eq 0 ]
  [ "$output" = "pen_myproject_auth-refactor" ]
  cd /tmp
  rm -rf "$tmpdir"
}

@test "script sources without errors" {
  # Verified by reaching this point; setup() sources the script
  true
}

# ---------------------------------------------------------------------------
# _is_pen_container
# ---------------------------------------------------------------------------

@test "_is_pen_container: returns true for a known pen container" {
  docker() {
    local args="$*"
    if [[ "$args" == *"name=^pen-foo"* && "$args" == *"label=pen=true"* ]]; then
      echo "fakeid"
    fi
  }
  run _is_pen_container "pen-foo"
  [ "$status" -eq 0 ]
}

@test "_is_pen_container: returns false for an unknown container" {
  docker() { true; }  # always returns empty
  run _is_pen_container "not-a-pen"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# cmd_stop with explicit container name
# ---------------------------------------------------------------------------

@test "cmd_stop: rejects a non-pen container name with error" {
  docker() { true; }  # _is_pen_container returns empty → not a pen container
  run cmd_stop "not-a-pen"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a pen container"* ]]
}

@test "cmd_stop: stops and removes a valid pen container by name" {
  docker() {
    case "$1" in
      ps)
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

@test "cmd_stop: reports missing container for a valid pen name that no longer exists" {
  docker() {
    case "$1" in
      ps)
        # _is_pen_container passes (has label filter): container is known pen container
        if [[ "$*" == *"label=pen=true"* && "$*" == *"name=^gone-container"* ]]; then
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

@test "cmd_exec: rejects a non-pen container name with error" {
  docker() { true; }
  run cmd_exec "not-a-pen"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a pen container"* ]]
}

@test "cmd_exec: reports error when pen container exists but is not running" {
  docker() {
    case "$1" in
      ps)
        # _is_pen_container (with -aq and label filter): passes
        if [[ "$*" == *"label=pen=true"* && "$*" == *"name=^stopped-container"* ]]; then
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
    if [[ "$*" == *"label=pen=true"* && "$*" == *"{{.Names}}"* ]]; then
      echo "pen-foo"
      echo "pen-bar"
    fi
  }
  run cmd_list "--names-only"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pen-foo" ]
  [ "${lines[1]}" = "pen-bar" ]
}

@test "cmd_list: --names-only produces no table header" {
  docker() {
    if [[ "$*" == *"label=pen=true"* && "$*" == *"{{.Names}}"* ]]; then
      echo "pen-foo"
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

# ---------------------------------------------------------------------------
# cmd_launch: live mounts for host CLAUDE.md and commands/
# ---------------------------------------------------------------------------

# Helper: create a minimal fake HOME with .claude and .pen/claude dirs
_setup_fake_home() {
  local fake_home="$1"
  mkdir -p "${fake_home}/.claude/commands"
  touch "${fake_home}/.claude/CLAUDE.md"
  touch "${fake_home}/.claude/commands/test-cmd.md"
  mkdir -p "${fake_home}/.pen/claude"
}

# Helper: mock docker for a new (non-running) container; logs docker run args to a file
_mock_docker_new() {
  cat > "${MOCK_BIN}/docker" << EOF
#!/usr/bin/env bash
case "\$1" in
  ps)   echo "" ;;
  run)  echo "\$@" >> "${MOCK_BIN}/.docker_run_log" ;;
  exec) echo "\$@" ;;
esac
EOF
  chmod +x "${MOCK_BIN}/docker"
}

@test "cmd_launch: mounts host CLAUDE.md read-only into container" {
  local fake_home
  fake_home=$(mktemp -d)
  _setup_fake_home "$fake_home"
  _mock_docker_new
  HOME="$fake_home" HARNESS_CONFIG="${fake_home}/.pen/claude" run cmd_launch
  local run_args
  run_args=$(cat "${MOCK_BIN}/.docker_run_log" 2>/dev/null)
  [[ "$run_args" == *"${fake_home}/.claude/CLAUDE.md:/home/pen/.claude/CLAUDE.md:ro"* ]]
  rm -rf "$fake_home"
}

@test "cmd_launch: mounts host commands dir read-only into container" {
  local fake_home
  fake_home=$(mktemp -d)
  _setup_fake_home "$fake_home"
  _mock_docker_new
  HOME="$fake_home" HARNESS_CONFIG="${fake_home}/.pen/claude" run cmd_launch
  local run_args
  run_args=$(cat "${MOCK_BIN}/.docker_run_log" 2>/dev/null)
  [[ "$run_args" == *"${fake_home}/.claude/commands:/home/pen/.claude/commands:ro"* ]]
  rm -rf "$fake_home"
}

@test "cmd_launch: does not mount CLAUDE.md when source does not exist" {
  local fake_home
  fake_home=$(mktemp -d)
  mkdir -p "${fake_home}/.pen/claude"
  _mock_docker_new
  HOME="$fake_home" HARNESS_CONFIG="${fake_home}/.pen/claude" run cmd_launch
  local run_args
  run_args=$(cat "${MOCK_BIN}/.docker_run_log" 2>/dev/null)
  [[ "$run_args" != *"CLAUDE.md:ro"* ]]
  rm -rf "$fake_home"
}

@test "cmd_launch: does not mount commands dir when source does not exist" {
  local fake_home
  fake_home=$(mktemp -d)
  mkdir -p "${fake_home}/.pen/claude"
  _mock_docker_new
  HOME="$fake_home" HARNESS_CONFIG="${fake_home}/.pen/claude" run cmd_launch
  local run_args
  run_args=$(cat "${MOCK_BIN}/.docker_run_log" 2>/dev/null)
  [[ "$run_args" != *"/commands:ro"* ]]
  rm -rf "$fake_home"
}

# ---------------------------------------------------------------------------
# cmd_sync
# ---------------------------------------------------------------------------

_require_jq() {
  command -v jq &>/dev/null || skip "jq not available"
}

@test "cmd_sync: creates pen settings from host, stripping hooks and mcpServers" {
  _require_jq
  local fake_home
  fake_home=$(mktemp -d)
  mkdir -p "${fake_home}/.claude" "${fake_home}/.pen/claude"
  printf '%s\n' '{"theme":"dark","hooks":{"Stop":[]},"mcpServers":{"s":{"command":"x"}},"env":{"DISABLE_AUTOUPDATER":1}}' \
    > "${fake_home}/.claude/settings.json"
  HOME="$fake_home" HARNESS_CONFIG="${fake_home}/.pen/claude" run cmd_sync --yes
  [ "$status" -eq 0 ]
  local result
  result=$(cat "${fake_home}/.pen/claude/settings.json")
  [[ "$result" == *'"dark"'* ]]
  [[ "$result" == *"DISABLE_AUTOUPDATER"* ]]
  [[ "$result" != *'"hooks"'* ]]
  [[ "$result" != *'"mcpServers"'* ]]
  [[ "$result" == *'"skipDangerousModePermissionPrompt"'* ]]
  rm -rf "$fake_home"
}

@test "cmd_sync: always sets skipDangerousModePermissionPrompt true even when absent from source" {
  _require_jq
  local fake_home
  fake_home=$(mktemp -d)
  mkdir -p "${fake_home}/.claude" "${fake_home}/.pen/claude"
  printf '%s\n' '{"theme":"dark"}' > "${fake_home}/.claude/settings.json"
  HOME="$fake_home" HARNESS_CONFIG="${fake_home}/.pen/claude" run cmd_sync --yes
  [ "$status" -eq 0 ]
  local result
  result=$(cat "${fake_home}/.pen/claude/settings.json")
  [[ "$result" == *'"skipDangerousModePermissionPrompt": true'* ]]
  rm -rf "$fake_home"
}

@test "cmd_sync: preserves pen hooks and mcpServers when merging" {
  _require_jq
  local fake_home
  fake_home=$(mktemp -d)
  mkdir -p "${fake_home}/.claude" "${fake_home}/.pen/claude"
  printf '%s\n' '{"theme":"dark","hooks":{"Stop":[{"command":"host-hook"}]}}' \
    > "${fake_home}/.claude/settings.json"
  printf '%s\n' '{"hooks":{"Stop":[{"command":"pen-hook"}]},"mcpServers":{"readonly-mcp":{"command":"bar"}}}' \
    > "${fake_home}/.pen/claude/settings.json"
  HOME="$fake_home" HARNESS_CONFIG="${fake_home}/.pen/claude" run cmd_sync --yes
  [ "$status" -eq 0 ]
  local result
  result=$(cat "${fake_home}/.pen/claude/settings.json")
  [[ "$result" == *"pen-hook"* ]]
  [[ "$result" != *"host-hook"* ]]
  [[ "$result" == *"readonly-mcp"* ]]
  [[ "$result" == *'"dark"'* ]]
  rm -rf "$fake_home"
}

@test "cmd_sync: reports already in sync when settings are identical" {
  _require_jq
  local fake_home
  fake_home=$(mktemp -d)
  mkdir -p "${fake_home}/.claude" "${fake_home}/.pen/claude"
  printf '%s\n' '{"theme":"dark"}' > "${fake_home}/.claude/settings.json"
  # Pre-populate pen config with the already-merged result
  jq 'del(.hooks, .mcpServers) + {skipDangerousModePermissionPrompt: true}' \
    "${fake_home}/.claude/settings.json" > "${fake_home}/.pen/claude/settings.json"
  HOME="$fake_home" HARNESS_CONFIG="${fake_home}/.pen/claude" run cmd_sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"already in sync"* ]]
  rm -rf "$fake_home"
}

@test "cmd_sync: shows diff preview when changes exist and no --yes flag" {
  _require_jq
  local fake_home
  fake_home=$(mktemp -d)
  mkdir -p "${fake_home}/.claude" "${fake_home}/.pen/claude"
  printf '%s\n' '{"theme":"dark"}' > "${fake_home}/.claude/settings.json"
  printf '%s\n' '{"theme":"light"}' > "${fake_home}/.pen/claude/settings.json"
  # Non-interactive (stdin from /dev/null, not a TTY): should show diff and exit non-zero
  HOME="$fake_home" HARNESS_CONFIG="${fake_home}/.pen/claude" run cmd_sync < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"--yes"* ]]
  # File should be unchanged
  [[ "$(cat "${fake_home}/.pen/claude/settings.json")" == *"light"* ]]
  rm -rf "$fake_home"
}

@test "cmd_sync: errors when source settings.json does not exist" {
  local fake_home
  fake_home=$(mktemp -d)
  mkdir -p "${fake_home}/.pen/claude"
  HOME="$fake_home" HARNESS_CONFIG="${fake_home}/.pen/claude" run cmd_sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"No source settings"* ]]
  rm -rf "$fake_home"
}

# ---------------------------------------------------------------------------
# _read_toml_str
# ---------------------------------------------------------------------------

@test "_read_toml_str: extracts a string value from TOML file" {
  local tmpfile; tmpfile=$(mktemp)
  printf 'harness = "cursor"\n' > "$tmpfile"
  run _read_toml_str "$tmpfile" harness
  [ "$status" -eq 0 ]
  [ "$output" = "cursor" ]
  rm -f "$tmpfile"
}

@test "_read_toml_str: returns empty when key not found" {
  local tmpfile; tmpfile=$(mktemp)
  printf 'other = "value"\n' > "$tmpfile"
  run _read_toml_str "$tmpfile" harness
  [ "$output" = "" ]
  rm -f "$tmpfile"
}

# ---------------------------------------------------------------------------
# resolve_harness
# ---------------------------------------------------------------------------

@test "resolve_harness: defaults to claude when no config or flag" {
  local tmpdir; tmpdir=$(mktemp -d)
  cat > "${MOCK_BIN}/git" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${MOCK_BIN}/git"
  CLI_HARNESS="" HOME="$tmpdir" run resolve_harness
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
  rm -rf "$tmpdir"
}

@test "resolve_harness: reads harness from .pen.toml in git root" {
  local tmpdir; tmpdir=$(mktemp -d)
  printf 'harness = "cursor"\n' > "${tmpdir}/.pen.toml"
  cat > "${MOCK_BIN}/git" << EOF
#!/usr/bin/env bash
echo "$tmpdir"
EOF
  chmod +x "${MOCK_BIN}/git"
  local fake_home; fake_home=$(mktemp -d)
  CLI_HARNESS="" HOME="$fake_home" run resolve_harness
  [ "$status" -eq 0 ]
  [ "$output" = "cursor" ]
  rm -rf "$tmpdir" "$fake_home"
}

@test "resolve_harness: uses user config.toml as fallback when no .pen.toml" {
  local fake_home; fake_home=$(mktemp -d)
  mkdir -p "${fake_home}/.pen"
  printf 'harness = "opencode"\n' > "${fake_home}/.pen/config.toml"
  cat > "${MOCK_BIN}/git" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${MOCK_BIN}/git"
  CLI_HARNESS="" HOME="$fake_home" run resolve_harness
  [ "$status" -eq 0 ]
  [ "$output" = "opencode" ]
  rm -rf "$fake_home"
}

@test "resolve_harness: CLI_HARNESS takes precedence over .pen.toml" {
  local tmpdir; tmpdir=$(mktemp -d)
  printf 'harness = "cursor"\n' > "${tmpdir}/.pen.toml"
  cat > "${MOCK_BIN}/git" << EOF
#!/usr/bin/env bash
echo "$tmpdir"
EOF
  chmod +x "${MOCK_BIN}/git"
  CLI_HARNESS="opencode" run resolve_harness
  [ "$status" -eq 0 ]
  [ "$output" = "opencode" ]
  rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# configure_harness
# ---------------------------------------------------------------------------

@test "configure_harness: sets expected globals for claude harness" {
  local fake_home; fake_home=$(mktemp -d)
  HARNESS=claude HOME="$fake_home" configure_harness
  [ "$HARNESS_IMAGE" = "pen-claude:latest" ]
  [ "$HARNESS_CONFIG" = "${fake_home}/.pen/claude" ]
  [ "$HARNESS_CONTAINER_CONFIG" = "/home/pen/.claude" ]
  rm -rf "$fake_home"
}

@test "configure_harness: PEN_IMAGE overrides default image" {
  local fake_home; fake_home=$(mktemp -d)
  HARNESS=claude HOME="$fake_home" PEN_IMAGE="myregistry/pen-claude:v2" configure_harness
  [ "$HARNESS_IMAGE" = "myregistry/pen-claude:v2" ]
  rm -rf "$fake_home"
}

@test "configure_harness: unknown harness exits with error" {
  HARNESS=unknownharness run configure_harness
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown harness"* ]]
}

@test "configure_harness: cursor harness exits with not-yet-implemented error" {
  HARNESS=cursor run configure_harness
  [ "$status" -ne 0 ]
  [[ "$output" == *"not yet implemented"* ]]
}

# ---------------------------------------------------------------------------
# cmd_sync: harness guard
# ---------------------------------------------------------------------------

@test "cmd_sync: errors when harness is not claude" {
  HARNESS=cursor run cmd_sync --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"only supported for the claude harness"* ]]
}

# ---------------------------------------------------------------------------
# cmd_help
# ---------------------------------------------------------------------------

@test "cmd_help: exits with status 0" {
  run cmd_help
  [ "$status" -eq 0 ]
}

@test "cmd_help: output contains Usage:" {
  run cmd_help
  [[ "$output" == *"Usage:"* ]]
}

@test "cmd_help: output mentions pen" {
  run cmd_help
  [[ "$output" == *"pen"* ]]
}

@test "cmd_help: documents -- passthrough" {
  run cmd_help
  [[ "$output" == *"--"* ]]
}

# ---------------------------------------------------------------------------
# cmd_version
# ---------------------------------------------------------------------------

@test "cmd_version: outputs 'pen' prefix" {
  PEN_VERSION="v9.9.9" run cmd_version
  [ "$status" -eq 0 ]
  [[ "$output" == pen* ]]
}

@test "cmd_version: includes PEN_VERSION when it is a real version string" {
  PEN_VERSION="v1.2.3" run cmd_version
  [ "$status" -eq 0 ]
  [[ "$output" == *"v1.2.3"* ]]
}

@test "cmd_version: falls back to git describe when PEN_VERSION is placeholder" {
  cat > "${MOCK_BIN}/git" << 'EOF'
#!/usr/bin/env bash
echo "v0.5.0"
EOF
  chmod +x "${MOCK_BIN}/git"
  PEN_VERSION="%%VERSION%%" run cmd_version
  [ "$status" -eq 0 ]
  [[ "$output" == *"v0.5.0"* ]]
}

@test "cmd_version: outputs 'unknown' when placeholder and git fails" {
  cat > "${MOCK_BIN}/git" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${MOCK_BIN}/git"
  PEN_VERSION="%%VERSION%%" run cmd_version
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]]
}

# ---------------------------------------------------------------------------
# container_name: pen_ prefix
# ---------------------------------------------------------------------------

@test "container_name: output is prefixed with pen_" {
  local tmpdir; tmpdir=$(mktemp -d /tmp/pen_test_XXXXX)
  cd "$tmpdir"
  run container_name
  [ "$status" -eq 0 ]
  [[ "$output" == pen_* ]]
  cd /tmp
  rm -rf "$tmpdir"
}

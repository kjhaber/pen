#!/usr/bin/env bash
# Integration tests: verify the Cursor Agent Docker image

set -euo pipefail

IMAGE="${PEN_IMAGE:-pen-cursor:latest}"
PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if docker run --rm "$IMAGE" "$@" > /dev/null 2>&1; then
    printf 'PASS  %s\n' "$desc"
    ((PASS++)) || true
  else
    printf 'FAIL  %s\n' "$desc"
    ((FAIL++)) || true
  fi
}

# Like check but runs as the current host user (mirrors runtime behaviour)
check_as_user() {
  local desc="$1"; shift
  if docker run --rm \
      --user "$(id -u):$(id -g)" \
      -e HOME=/home/pen \
      "$IMAGE" "$@" > /dev/null 2>&1; then
    printf 'PASS  %s\n' "$desc"
    ((PASS++)) || true
  else
    printf 'FAIL  %s\n' "$desc"
    ((FAIL++)) || true
  fi
}

echo "=== Cursor image tool checks (${IMAGE}) ==="
check_as_user "agent runs as non-root" sh -c 'id -u | grep -v "^0$"'
check "cursor-agent is installed" cursor-agent --version
check "agent symlink works" agent --version

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]

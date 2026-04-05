#!/usr/bin/env bash
# Integration tests: verify the Docker image contains all required tools

set -euo pipefail

IMAGE="${PEN_IMAGE:-pen-claude:latest}"
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
      -e HOME=/home/devcon \
      "$IMAGE" "$@" > /dev/null 2>&1; then
    printf 'PASS  %s\n' "$desc"
    ((PASS++)) || true
  else
    printf 'FAIL  %s\n' "$desc"
    ((FAIL++)) || true
  fi
}

echo "=== Image tool checks (${IMAGE}) ==="
check_as_user "claude runs as non-root" sh -c 'id -u | grep -v "^0$"'
check "claude is installed"     claude --version
check "git is installed"        git --version
check "go is installed"         go version
check "node is installed"       node --version
check "npm is installed"        npm --version
check "python3 is installed"    python3 --version
check "make is installed"       make --version
check "curl is installed"       curl --version
check "jq is installed"         jq --version
check "ripgrep (rg) installed"  rg --version
check "fzf is installed"        fzf --version

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]

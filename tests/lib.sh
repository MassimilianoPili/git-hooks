#!/bin/bash
# Shared helpers for the hook tests. Sourced, not run.
#
# Every test works in throwaway repos under a temporary directory and uses the
# hooks and pattern files of this repository, never the installed ones.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOKS="$REPO_ROOT/hooks"
export AI_ARTIFACTS_FILE="$REPO_ROOT/ai-artifacts.txt"
export AI_PATTERNS_FILE="$REPO_ROOT/ai-patterns.txt"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/git-hooks-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
NOHOOKS="$WORK/nohooks"
mkdir -p "$NOHOOKS"

# Temporary directories can belong to another user on Windows (sandboxes,
# elevated shells): trust them for this process tree only. core.autocrlf off,
# so the tests see the bytes they write.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
export GIT_CONFIG_KEY_1=core.autocrlf GIT_CONFIG_VALUE_1=false

FAILED=0

# git for test setup: hooks off, fixed identity.
g() {
  git -c core.hooksPath="$NOHOOKS" -c user.name=test -c user.email=test@example.com \
    -c commit.gpgsign=false "$@"
}

# New repo in $WORK/$1, current directory moves there.
mkrepo() {
  rm -rf "${WORK:?}/$1"
  mkdir -p "$WORK/$1"
  cd "$WORK/$1" || exit 1
  g init -q -b main
}

check() { # $1 description, $2 actual, $3 expected
  if [ "$2" == "$3" ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1"
    echo "      expected: $3"
    echo "      actual:   $2"
    FAILED=1
  fi
}

staged() { git diff --cached --name-only | sort | paste -sd',' -; }

# Elapsed milliseconds of a command, its output discarded.
ms() {
  local start end
  start=$(date +%s%N)
  "$@" > /dev/null 2>&1
  end=$(date +%s%N)
  echo $(( (end - start) / 1000000 ))
}

finish() {
  if [ "$FAILED" -eq 0 ]; then
    echo "ALL PASSED"
  else
    echo "SOME TESTS FAILED"
  fi
  exit "$FAILED"
}

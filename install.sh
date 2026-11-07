#!/bin/bash
# install.sh: installs the hooks and the pattern files into ~/.config/git and
# points the global core.hooksPath there.
#
#   ./install.sh             install; whatever it replaces is backed up first
#   ./install.sh --patterns  also overwrite pattern files you have customized
#   ./install.sh --check     compare this repository with the installed copy,
#                            exit 1 if they differ (nothing is written)
#
# GIT_HOOKS_HOME overrides the destination (default ~/.config/git).

set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
DEST="${GIT_HOOKS_HOME:-${HOME}/.config/git}"
MODE=install
OVERWRITE_PATTERNS=0
for arg in "$@"; do
  case $arg in
    --check) MODE=check ;;
    --patterns) OVERWRITE_PATTERNS=1 ;;
    *) echo "usage: $0 [--check] [--patterns]" >&2; exit 2 ;;
  esac
done

PATTERN_FILES=(ai-artifacts.txt ai-patterns.txt)
mapfile -t HOOK_FILES < <(cd "$SRC" && find hooks -type f | sort)

# Paths compare in one form on Windows (C:/x) and as they are elsewhere.
norm() {
  if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

check() {
  local drift=0 file hooks_path
  for file in "${HOOK_FILES[@]}" "${PATTERN_FILES[@]}"; do
    if [ ! -f "$DEST/$file" ]; then
      echo "missing   $DEST/$file"; drift=1
    elif ! cmp -s "$SRC/$file" "$DEST/$file"; then
      echo "differs   $DEST/$file"; drift=1
    fi
  done
  # Extra files in the installed hooks directory run too (the dispatchers run
  # every executable file in the .d directories).
  while IFS= read -r file; do
    [[ " ${HOOK_FILES[*]} " == *" $file "* ]] || { echo "extra     $DEST/$file"; drift=1; }
  done < <(cd "$DEST" 2>/dev/null && find hooks -type f 2>/dev/null | sort)
  hooks_path=$(git config --global --get core.hooksPath || true)
  if [ -z "$hooks_path" ] || [ "$(norm "$hooks_path")" != "$(norm "$DEST/hooks")" ]; then
    echo "hooksPath core.hooksPath is '${hooks_path}', expected '$DEST/hooks'"; drift=1
  fi
  if [ "$drift" -eq 0 ]; then
    echo "OK: $DEST matches $SRC"
  fi
  return "$drift"
}

if [ "$MODE" = check ]; then
  check
  exit $?
fi

# Back up every file this run is about to replace.
BACKUP="$DEST/hooks-backup/$(date +%Y%m%d-%H%M%S)"
backup() { # $1 path relative to DEST
  if [ -f "$DEST/$1" ] && ! cmp -s "$SRC/$1" "$DEST/$1"; then
    mkdir -p "$BACKUP/$(dirname "$1")"
    cp -p "$DEST/$1" "$BACKUP/$1"
  fi
}

for file in "${HOOK_FILES[@]}"; do
  backup "$file"
  mkdir -p "$DEST/$(dirname "$file")"
  cp "$SRC/$file" "$DEST/$file"
  chmod +x "$DEST/$file"
done

for file in "${PATTERN_FILES[@]}"; do
  if [ ! -f "$DEST/$file" ] || [ "$OVERWRITE_PATTERNS" -eq 1 ]; then
    backup "$file"
    cp "$SRC/$file" "$DEST/$file"
  elif ! cmp -s "$SRC/$file" "$DEST/$file"; then
    echo "kept      $DEST/$file (yours differs from the repository; --patterns overwrites it)"
  fi
done

[ -d "$BACKUP" ] && echo "backup    $BACKUP"

hooks_path=$(git config --global --get core.hooksPath || true)
if [ -z "$hooks_path" ]; then
  git config --global core.hooksPath "$DEST/hooks"
  echo "set       core.hooksPath = $DEST/hooks"
elif [ "$(norm "$hooks_path")" != "$(norm "$DEST/hooks")" ]; then
  echo "WARNING   core.hooksPath is '$hooks_path', not changed. To use these hooks:" >&2
  echo "          git config --global core.hooksPath \"$DEST/hooks\"" >&2
fi

check || true

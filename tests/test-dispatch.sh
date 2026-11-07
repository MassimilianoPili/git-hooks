#!/bin/bash
# Tests for the dispatchers (pre-commit, commit-msg, pre-push), the commit-msg
# strip and the pre-push guard. Git runs the hooks itself (git hook run), so
# $0 and stdin look as they do in a real commit or push; nothing is committed.
. "$(dirname "$0")/lib.sh"

hook() { git -c core.hooksPath="$HOOKS" hook run "$@"; }

echo "== pre-commit dispatcher runs every hook in pre-commit.d"
mkrepo dispatch
echo base > base.txt; g add base.txt; g commit -qm base
mkdir -p .claude; echo s > .claude/settings.local.json
printf 'code\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > app.txt
g add -A
hook pre-commit > /dev/null
check "artifact unstaged and attribution stripped" "$(staged):$(git show :app.txt)" "app.txt:code"

echo "== dispatcher chains to the repository's own hook"
printf '#!/bin/bash\ntouch "%s/local-ran"\n' "$WORK" > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
hook pre-commit > /dev/null
check "local .git/hooks/pre-commit ran" "$([ -f "$WORK/local-ran" ] && echo yes || echo no)" "yes"

echo "== commit-msg strips attribution and trailing blank lines"
printf 'feat: add thing\n\nBody line.\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n\n\n' > "$WORK/msg"
hook commit-msg -- "$WORK/msg" > /dev/null
check "message" "$(paste -sd'|' - < "$WORK/msg")" "feat: add thing||Body line."

echo "== pre-push refuses a remote delete, lets a normal push through"
zero=0000000000000000000000000000000000000000
sha=$(git rev-parse HEAD)
printf '(delete) %s refs/heads/old %s\n' "$zero" "$sha" > "$WORK/refs-delete"
hook pre-push --to-stdin="$WORK/refs-delete" -- origin https://example.invalid/repo.git > /dev/null 2>&1
check "delete refused (exit 1)" "$?" "1"
printf 'refs/heads/main %s refs/heads/main %s\n' "$sha" "$zero" > "$WORK/refs-push"
hook pre-push --to-stdin="$WORK/refs-push" -- origin https://example.invalid/repo.git > /dev/null 2>&1
check "normal push allowed (exit 0)" "$?" "0"

finish

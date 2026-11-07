#!/bin/bash
# Tests for hooks/pre-commit.d/block-ai-artifacts.
. "$(dirname "$0")/lib.sh"
HOOK="$HOOKS/pre-commit.d/block-ai-artifacts"

echo "== no artifact staged"
mkrepo plain
echo base > base.txt; g add base.txt; g commit -qm base
for i in $(seq 1 20); do echo "$i" > "f$i.txt"; done
g add -A
bash "$HOOK" > /dev/null
check "20 staged files stay staged" "$(git diff --cached --name-only | wc -l | tr -d ' ')" "20"

echo "== many staged files, some artifacts"
mkrepo many
echo base > base.txt; g add base.txt; g commit -qm base
mkdir -p src .claude/agents
for i in $(seq 1 300); do echo "$i" > "src/f$i.txt"; done
for i in $(seq 1 30); do echo "$i" > ".claude/agents/a$i.md"; done
g add -A
t=$(ms bash "$HOOK")
check "300 files staged, .claude/ unstaged" \
  "$(git diff --cached --name-only | wc -l | tr -d ' ') $(git diff --cached --name-only | grep -c '^\.claude/')" "300 0"
check ".claude/ files kept on disk" "$(ls .claude/agents | wc -l | tr -d ' ')" "30"
echo "      (${t} ms)"

echo "== special names and anchors"
mkrepo names
echo base > base.txt; g add base.txt; g commit -qm base
mkdir -p .claude
echo x > ".claude/a b[1].md"; echo x > ".claude/città.md"; echo x > .windsurfrules
echo x > .windsurfrules.txt; echo x > CLAUDE.md
g add -A
bash "$HOOK" > /dev/null
check "spaces, brackets, non-ASCII, .windsurfrules unstaged; CLAUDE.md kept" "$(staged)" ".windsurfrules.txt,CLAUDE.md"

echo "== first commit (unborn branch)"
mkrepo unborn
mkdir -p .claude; echo x > .claude/settings.local.json; echo x > a.txt
g add -A
bash "$HOOK" > /dev/null
check "artifact unstaged without HEAD" "$(staged)" "a.txt"

echo "== merge commit"
mkrepo merge
mkdir -p .claude; echo v1 > .claude/settings.json; echo base > conflict.txt
g add -A; g commit -qm base
g checkout -qb feature
echo v2 > .claude/settings.json; mkdir -p .claude/agents; echo new > .claude/agents/x.md
echo feature > conflict.txt
g add -A; g commit -qm feature
g checkout -q main; echo main > conflict.txt; g commit -qam main
g merge -q feature > /dev/null 2>&1
echo resolved > conflict.txt; echo session > .claude/settings.local.json
g add -A
bash "$HOOK" > /dev/null
check "paths tracked on a parent stay, new session file goes" "$(staged)" ".claude/agents/x.md,.claude/settings.json,conflict.txt"
check "merged content not reverted" "$(git show :.claude/settings.json)" "v2"

echo "== tracked artifact modified in a normal commit"
mkrepo tracked
mkdir -p .claude; echo v1 > .claude/settings.json; g add -A; g commit -qm base
echo v2 > .claude/settings.json; echo y > b.txt; g add -A
bash "$HOOK" > /dev/null
check "modification unstaged" "$(staged)" "b.txt"

echo "== invalid pattern"
mkrepo badregex
echo base > base.txt; g add base.txt; g commit -qm base
echo x > a.txt; g add a.txt
printf '(unclosed\n' > "$WORK/bad-patterns.txt"
AI_ARTIFACTS_FILE="$WORK/bad-patterns.txt" bash "$HOOK" > /dev/null 2>&1
check "hook stops the commit" "$?" "1"

finish

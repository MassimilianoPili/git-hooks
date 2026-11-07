#!/bin/bash
# Tests for hooks/pre-commit.d/strip-ai-attribution.
. "$(dirname "$0")/lib.sh"
HOOK="$HOOKS/pre-commit.d/strip-ai-attribution"

# The tool name comes from a variable: a literal "Generated with <tool>" line in
# this file would be stripped by the installed hook when the file is committed.
AI=Claude

lines() { printf '%s' "$1" | paste -sd'|' -; }
cr_count() { od -An -v -tx1 | tr ' ' '\n' | grep -c '^0d$'; }

echo "== partial staging (git add -p)"
mkrepo partial
printf 'line1\n' > f.txt; g add f.txt; g commit -qm base
printf 'line1\nCo-Authored-By: Claude <noreply@anthropic.com>\nCo-Authored-By: Claudette Rossi\n   // AI-generated code.\nstaged\n' > f.txt
g add f.txt
printf 'unstaged\n' >> f.txt
bash "$HOOK" > /dev/null
check "index: attribution gone, unstaged hunk not staged, word boundary kept Claudette" \
  "$(lines "$(git show :f.txt)")" "line1|Co-Authored-By: Claudette Rossi|staged"
check "working tree: attribution gone, unstaged hunk kept" \
  "$(lines "$(cat f.txt)")" "line1|Co-Authored-By: Claudette Rossi|staged|unstaged"

echo "== binary file"
mkrepo binary
echo base > base.txt; g add base.txt; g commit -qm base
printf 'Generated with %s\n\000\001\002\n' "$AI" > bin.dat; g add bin.dat
before=$(git rev-parse :bin.dat)
bash "$HOOK" > /dev/null
check "binary blob untouched" "$(git rev-parse :bin.dat)" "$before"

echo "== special name, CRLF, first commit"
mkrepo misc
mkdir -p docs
printf 'a\nGenerated with %s Code\nb\n' "$AI" > "docs/a b[1].md"
printf 'a\r\nCo-Authored-By: Claude <noreply@anthropic.com>\r\nb\r\n' > crlf.txt
g add -A
bash "$HOOK" > /dev/null
check "name with spaces and brackets stripped" "$(lines "$(git show ':docs/a b[1].md')")" "a|b"
check "CRLF kept in the index (2 CR left)" "$(git cat-file blob :crlf.txt | cr_count)" "2"
check "CRLF kept in the working tree (2 CR left)" "$(cr_count < crlf.txt)" "2"

echo "== attribution committed earlier, not staged"
mkrepo committed
printf 'doc\nGenerated with %s Code\n' "$AI" > old.md; g add old.md; g commit -qm base
echo clean > new.txt; g add new.txt
bash "$HOOK" > /dev/null
check "hook exits 0" "$?" "0"
check "committed file untouched" "$(lines "$(git show :old.md)")" "doc|Generated with $AI Code"

echo "== many staged files, few with attribution"
mkrepo many
echo base > base.txt; g add base.txt; g commit -qm base
mkdir -p src
for i in $(seq 1 300); do echo "$i" > "src/f$i.txt"; done
for i in 1 2 3; do printf 'x\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > "src/f$i.txt"; done
g add -A
t=$(ms bash "$HOOK")
check "no staged file keeps the attribution" "$(git grep --cached -l -i 'Co-Authored-By: Claude' | wc -l | tr -d ' ')" "0"
echo "      (${t} ms)"

finish

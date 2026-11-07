# git-hooks

Global git hooks that keep AI tool artifacts and AI attribution out of your commits.

They are written for Git Bash on Windows, where starting a process is slow. Each hook starts
a fixed number of processes per commit, however many files are staged.

## What the hooks do

| Hook | Effect |
|---|---|
| `pre-commit.d/block-ai-artifacts` | Unstages files of AI tools (`.claude/`, `.copilot/`, `.cursor/`, `.continue/`, `.windsurf/`, `.codeium/`, `.aider*`, `.windsurfrules`). The files stay on disk. |
| `pre-commit.d/strip-ai-attribution` | Removes attribution lines (`Co-Authored-By: Claude ...`, `Generated with ...`, "AI-generated code" comments) from the staged content. |
| `commit-msg.d/strip-ai-attribution` | Removes the `Co-Authored-By` and `Generated with` lines from the commit message. |
| `pre-push.d/10-no-remote-delete` | Refuses to delete a remote ref (`git push --delete`, `git push origin :branch`). |

The path patterns are in `ai-artifacts.txt`. The attribution patterns are in `ai-patterns.txt`.

## How they work

- **Dispatchers.** `hooks/pre-commit`, `hooks/commit-msg` and `hooks/pre-push` run every
  executable file in the matching `.d` directory, in name order. Then they run the repository's
  own `.git/hooks/<name>`, if there is one: a global `core.hooksPath` hides it otherwise.
- **Fixed cost.** On a Windows 11 laptop with endpoint protection, a process start costs about
  0.3 s. Earlier versions of these hooks started processes for each staged file:

  | Case | Before | Now |
  |---|---|---|
  | `block-ai-artifacts`, 800 staged files | 457 s | 2.3 s |
  | `strip-ai-attribution`, 800 staged files | 304 s | 1 process if no file has attribution |
  | `pre-commit` + `commit-msg`, usual commit | about 22 processes | about 11 processes |

  A file that does contain attribution costs about 8 processes to rewrite.
- **Merge commits.** `block-ai-artifacts` unstages only paths that no parent has. A path that a
  parent already tracks stays in the commit. If it were unstaged, the merge commit would revert
  that branch's content without telling you.
- **Staged content only.** `strip-ai-attribution` rewrites the staged blob and, separately, the
  file on disk. Hunks that you left out with `git add -p` stay out. Binary files are skipped.
  CRLF files stay CRLF.
- **Errors stop the commit.** An invalid pattern or a failed `git` command stops the commit with
  a message. The hooks never let it through as if nothing happened.

## Install

```bash
git clone https://github.com/MassimilianoPili/git-hooks.git
cd git-hooks
./install.sh
```

`install.sh` copies the hooks and the pattern files to `~/.config/git` (`GIT_HOOKS_HOME`
changes the destination). It backs up every file it replaces to
`~/.config/git/hooks-backup/<timestamp>/`. If `core.hooksPath` is not set, it sets it. If
`core.hooksPath` points somewhere else, the script only prints the command to change it.

Pattern files that you have changed are kept. `./install.sh --patterns` overwrites them.

`./install.sh --check` compares the repository with the installed copy and writes nothing. It
exits with 1 if a file is missing, differs, or is extra, or if `core.hooksPath` points
somewhere else.

## Customize

- **Patterns.** Edit `~/.config/git/ai-artifacts.txt` and `~/.config/git/ai-patterns.txt`. Each
  line is one extended regular expression, and lines that start with `#` are comments. Path
  patterns match repository-relative paths: `(^|/)\.claude/` matches `.claude/x` and
  `sub/.claude/x`, but not `CLAUDE.md`. Attribution patterns match one line at a time and
  ignore case.
- **Other pattern files.** `AI_ARTIFACTS_FILE` and `AI_PATTERNS_FILE` override the two paths.
- **Your own hooks.** Put an executable script in `hooks/<name>.d/`.
- **Skip the hooks once.** `git commit --no-verify` skips `pre-commit` and `commit-msg`.

## Tests

```bash
bash tests/test-block.sh
bash tests/test-strip.sh
bash tests/test-dispatch.sh
```

The tests create throwaway repositories in a temporary directory. They use the hooks and the
pattern files of this repository, never the installed ones. `test-dispatch.sh` lets git run
the hooks itself (`git hook run`), so nothing is committed.

## Requirements and limits

- Tested with Git for Windows 2.53 (Git Bash, GNU grep). On Linux or macOS you need bash 4.4 or
  later and GNU grep. macOS ships bash 3.2.
- A merge without conflicts runs `pre-merge-commit`, not `pre-commit`, and this repository has
  no `pre-merge-commit` hook. Such a merge contains only paths from its parents, so
  `block-ai-artifacts` would have nothing to unstage.
- `block-ai-artifacts` also unstages changes to an artifact path that is already tracked. If a
  repository keeps `.claude/` under version control on purpose, commit those changes with
  `--no-verify`.
- `strip-ai-attribution` removes every line that matches a pattern. This includes
  documentation lines that quote such a line.

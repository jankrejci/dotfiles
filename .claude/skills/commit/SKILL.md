---
name: commit
description: Creates atomic git commits with chunk-based staging and the gitlint-gated message format. Use when committing staged or unstaged changes, or when the user asks to commit or to split work into commits.
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
---

Create atomic commits for staged/unstaged changes using chunk-based staging.

Follow the commit format from CLAUDE.md. Title must match `^[a-z][a-z0-9-]*: [A-Z]`, max 72 chars. Body must explain WHY, not WHAT.

## Process

1. Run `git status` and `git diff` to understand all changes
2. Run `git log -5 --oneline` to see recent commit style
3. Identify logical groups of changes that belong together
4. For each logical group:
   - Stage specific chunks with `git add -p <file>` for modified files
   - For new files: `git add -N <file> && git add -p <file>`
   - Verify staged changes: `git diff --cached`
   - Run `nix flake check`
   - Create commit using HEREDOC:
     ```bash
     git commit -m "$(cat <<'EOF'
     module: Title here

     - why this change was needed
     - why this approach if non-obvious
     EOF
     )"
     ```
5. Run `git log --oneline -5` to verify
6. Run `nix run nixpkgs#gitlint -- --commits origin/main..HEAD` to validate all branch commit messages

## Fixup Commits

For iterations after review feedback, use fixup commits:
```bash
git commit --fixup=HEAD
```

Or target a specific commit:
```bash
git commit --fixup=<commit-hash>
```

Fixups will be squashed later with `/branch-cleanup`.

## Chunk Staging Reference

Interactive patch mode (`git add -p`) commands:
- `y` - stage this hunk
- `n` - skip this hunk
- `s` - split into smaller hunks
- `q` - quit, do not stage remaining hunks

## Rules

- One logical change per commit
- Separate unrelated changes into different commits
- NEVER push to remote
- NEVER use --amend unless explicitly requested
- NEVER skip nix flake check

**Commit separation — do not bundle these with source code:**
- `flake.lock` gets its own commit, never bundled with source changes
- `.claude/` config and `CLAUDE.md` get their own commit, never bundled
  with code or with each other
- Exception: bundle when separation would leave either commit unable to
  pass `nix flake check` — e.g. introducing a new module and its wiring
  together
- Exception: bundle when it is a single atomic move of content between
  `CLAUDE.md` and a `.claude/` file plus its pointer — splitting only
  duplicates or dangles the moved text across an intermediate commit

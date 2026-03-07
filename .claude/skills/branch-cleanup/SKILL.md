---
name: branch-cleanup
description: Rebase operations for cleaning up branch history before merge
disable-model-invocation: true
allowed-tools: Bash, Read, Edit
---

Rebase toolkit for branch history management. Default operation is conservative
autosquash of fixup commits. All other operations require explicit user request.

## Core Technique: GIT_SEQUENCE_EDITOR

All rebase operations use `GIT_SEQUENCE_EDITOR` to avoid interactive editors.
This is the only safe way for an AI agent to perform interactive rebase.

```bash
# No-op editor for autosquash-only rebases
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/main

# sed for targeted operations on specific commits
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i origin/main

# Multiple commits in a single rebase
GIT_SEQUENCE_EDITOR="sed -i -e 's/^pick <HASH1>/edit <HASH1>/' -e 's/^pick <HASH2>/edit <HASH2>/'" git rebase -i origin/main

# Bash script for complex todo list rewrites like reordering
GIT_SEQUENCE_EDITOR='bash -c "
  LINE=$(grep \"^pick <HASH>\" \"\$1\")
  sed -i \"/^pick <HASH>/d\" \"\$1\"
  sed -i \"/^pick <TARGET_HASH>/a\\\\$LINE\" \"\$1\"
"' git rebase -i origin/main
```

## Pre-flight (before every rebase)

1. Verify clean working tree: `git status`
2. Create timestamped backup: `git branch backup-$(git branch --show-current)-$(date +%s)`
3. Show current commits: `git log --oneline origin/main..HEAD`

## Default Operation: Autosquash Fixups

### Step 1: Validate fixup targets

```bash
git log --oneline origin/main..HEAD | grep 'fixup!'
```

For each fixup, confirm the target commit message exists in the branch.
Warn the user if a fixup has no valid target.

### Step 2: Autosquash

```bash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/main
```

This ONLY folds fixup!/squash! commits into their targets. Normal commits
are untouched.

### Step 3: Verify commit messages

Fixups may have changed a commit's content so the message no longer matches.
For each commit on the branch:

1. Read the commit: `git show <hash>`
2. Check if the message still accurately describes the diff
3. If mismatched, use the "Reword a Commit" operation below

### Step 4: Final verification

1. Diff against backup must be empty: `git diff backup-<branch>-<ts>..HEAD`
2. `nix flake check`
3. Show before/after commit list to user

## Rebase Operations

The following operations are only performed when the user explicitly asks
or as part of review fixes. Never apply them unprompted.

### Edit a Commit (modify content in place)

Use when: a commit needs its content changed without splitting. This is the
most common rebase operation for fixing review findings, removing lines,
or adjusting code in a specific commit.

1. Mark the commit for editing:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i origin/main
   ```
2. The rebase pauses at the target commit. The working tree reflects the
   state as of that commit. Make the changes to the file.
3. Stage and amend:
   ```bash
   git add <modified-files>
   git commit --amend --no-edit
   ```
   Use `--amend -m "new message"` if the message also needs updating.
4. Continue:
   ```bash
   git rebase --continue
   ```

To edit multiple commits in one rebase, mark them all with a single sed
command using `-e` flags. The rebase will pause at each one in order.
After amending each, run `git rebase --continue` to advance to the next.

### Split a Commit

Use when: a commit bundles unrelated changes that belong in separate commits.

1. Mark for editing:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i origin/main
   ```
2. Undo the commit but keep changes in working tree:
   ```bash
   git reset HEAD~1
   ```
3. Re-commit in logical groups:
   ```bash
   git add <files-for-group-1> && git commit -m "..."
   git add <files-for-group-2> && git commit -m "..."
   ```
   For partial file splits, use `git add -p <file>` to stage individual hunks.
4. Continue:
   ```bash
   git rebase --continue
   ```

### Reword a Commit

Use when: a commit message is inaccurate or needs updating after fixup folding.

1. Mark for editing:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i origin/main
   ```
2. Amend with new message:
   ```bash
   git commit --amend -m "$(cat <<'EOF'
   module: New commit message

   - updated bullet points
   EOF
   )"
   ```
3. Continue:
   ```bash
   git rebase --continue
   ```

### Move Files Between Commits

Use when: specific files belong in a different commit.

1. Mark the source commit for editing:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i origin/main
   ```
2. Extract files from the commit:
   ```bash
   git reset HEAD^ -- <file1> <file2>
   git commit --amend --no-edit
   ```
3. Continue rebase: `git rebase --continue`
4. The extracted files are now uncommitted changes. Either:
   - Amend them into a later commit with a second edit rebase, or
   - Create a new commit and reorder it into place

### Reorder Commits

Use when: a commit needs to be at a different position in the branch.

1. Show current order: `git log --oneline origin/main..HEAD`
2. Move a commit after a different one:
   ```bash
   GIT_SEQUENCE_EDITOR='bash -c "
     LINE=$(grep \"^pick <HASH_TO_MOVE>\" \"\$1\")
     sed -i \"/^pick <HASH_TO_MOVE>/d\" \"\$1\"
     sed -i \"/^pick <TARGET_HASH>/a\\\\$LINE\" \"\$1\"
   "' git rebase -i origin/main
   ```
3. Handle any conflicts from the new order.

### Drop a Commit

Use when: a commit should be removed entirely.

```bash
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/drop <HASH>/'" git rebase -i origin/main
```

### Full Soft Reset (last resort)

Use when: commits are too interleaved to rebase cleanly. Requires user
confirmation before proceeding.

1. `git reset --soft origin/main`
2. `git reset HEAD -- .`
3. Stage and commit in logical groups using `/commit` skill
4. Verify: `nix flake check`

## Conflict Handling

When a rebase encounters a conflict:

1. **Investigate first**: read the conflict markers and understand both sides.
   Check what the target branch changed:
   ```bash
   git log -p -n 3 origin/main -- <conflicting-file>
   ```
2. **Simple conflicts** (few files, clear resolution): resolve the files,
   `git add <resolved-files>`, then `git rebase --continue`.
3. **Complex conflicts** (many files, unclear intent): abort immediately
   with `git rebase --abort` and inform the user. Suggest alternatives
   like soft reset or a different rebase strategy.
4. **NEVER escalate** from a failed rebase to `git reset --hard`,
   `git checkout -- .`, or other destructive commands. The only safe
   escape from a stuck rebase is `git rebase --abort`.

## Rules

- NEVER push to remote
- NEVER delete backup branch automatically
- NEVER use destructive commands (`reset --hard`, `checkout -- .`, `clean -f`)
- ALWAYS create backup branch before any rebase
- ALWAYS run `nix flake check` after rebase completes
- ALWAYS show before/after commit list to user
- ALWAYS abort rebase on unexpected conflicts rather than guessing

## Principles

- Preserve existing commits by default, only fold fixups
- Normal commits represent reviewed, intentional history
- Only restructure when the user explicitly asks
- Separate CLAUDE.md changes from code commits
- When in doubt, abort and ask the user

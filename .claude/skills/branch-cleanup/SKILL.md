---
name: branch-cleanup
description: Fold fixup commits via autosquash and verify commit messages still match diffs
disable-model-invocation: true
allowed-tools: Bash, Read
---

Fold fixup commits into their targets before merge. Default operation is conservative autosquash only. Normal commits are never squashed, reordered, or dropped unless the user explicitly requests it.

## Default Operation: Autosquash Fixups

### Step 0: Pre-flight

1. Verify clean working tree: `git status`
2. Create backup branch: `git branch backup-$(git branch --show-current)-$(date +%s)`
3. Show current commits: `git log --oneline origin/main..HEAD`
4. Verify fixup! commits exist and their targets are valid:
   ```bash
   git log --oneline origin/main..HEAD | grep 'fixup!'
   ```
   For each fixup, confirm the target commit message exists in the branch. If a fixup has no valid target, warn the user before proceeding.

### Step 1: Autosquash

```bash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/main
```

This ONLY folds fixup!/squash! commits into their targets. Normal commits are untouched.

### Step 2: Verify commit messages

After autosquash, fixups may have changed a commit's content so the message no longer matches. For each commit on the branch:

1. Read the commit: `git show <hash>`
2. Check if the message still accurately describes the diff
3. If the message no longer matches the content, reword it:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <SHORT_HASH>/reword <SHORT_HASH>/'" git rebase -i origin/main
   ```
   Then provide the corrected message when prompted.

### Step 3: Final verification

1. Compare with backup: `git diff backup-<branch>-<timestamp>..HEAD` must be empty
2. `nix flake check`
3. Show final commits: `git log --oneline origin/main..HEAD`
4. Show user the before/after comparison

## User-Requested Operations

The following operations are only performed when the user explicitly asks. Never apply them as part of default cleanup.

### Split a Commit

Use when: user asks to split a commit that bundles unrelated changes.

1. Identify the commit to split: `git log --oneline origin/main..HEAD`
2. Mark it for editing:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <SHORT_HASH>/edit <SHORT_HASH>/'" git rebase -i origin/main
   ```
3. At the paused commit, undo it but keep changes staged:
   ```bash
   git reset --soft HEAD^
   ```
4. Unstage everything:
   ```bash
   git reset HEAD -- .
   ```
5. Re-commit in logical groups:
   ```bash
   git add <files-for-group-1> && git commit -m "..."
   git add <files-for-group-2> && git commit -m "..."
   ```
6. Continue rebase:
   ```bash
   git rebase --continue
   ```

### Reorder Commits

Use when: user asks to move a commit to a different position.

1. Show current order: `git log --oneline origin/main..HEAD`
2. Use a script as GIT_SEQUENCE_EDITOR to rewrite the todo list:
   ```bash
   GIT_SEQUENCE_EDITOR='bash -c "
     LINE=$(grep \"^pick <HASH_TO_MOVE>\" \"\$1\")
     sed -i \"/^pick <HASH_TO_MOVE>/d\" \"\$1\"
     sed -i \"/^pick <HASH_AFTER>/a\\\\$LINE\" \"\$1\"
   "' git rebase -i origin/main
   ```
3. Resolve any conflicts that arise from the new order.

### Move Files Between Commits

Use when: user asks to move specific files from one commit to another.

1. Mark the source commit for editing:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <SHORT_HASH>/edit <SHORT_HASH>/'" git rebase -i origin/main
   ```
2. At the paused commit, extract the files:
   ```bash
   git reset HEAD^ -- <file1> <file2>
   git commit --amend --no-edit
   ```
3. Continue rebase: `git rebase --continue`
4. The extracted files are now uncommitted. Amend them into the correct commit using a second rebase, or commit as new and reorder.

### Drop a Commit

Use when: user asks to remove a commit entirely.

```bash
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <SHORT_HASH>/drop <SHORT_HASH>/'" git rebase -i origin/main
```

### Full Soft Reset (Last Resort)

Use when: user explicitly requests it because rebase cannot produce clean commits. Confirm with user before proceeding.

1. `git reset --soft origin/main`
2. `git reset HEAD -- .`
3. Stage and commit in logical groups using `/commit` skill
4. Verify: `nix flake check`

## Rules

- NEVER force push without user confirmation
- NEVER delete backup branch automatically
- ALWAYS verify `nix flake check` passes after rebase
- ALWAYS show before/after commit list to user

## Principles

- Preserve existing commits by default, only fold fixups
- Normal commits represent reviewed, intentional history
- Only consolidate or restructure when the user explicitly asks
- Separate CLAUDE.md changes from code commits
- When in doubt, do less and ask the user

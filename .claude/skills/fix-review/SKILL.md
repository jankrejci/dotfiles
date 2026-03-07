---
name: fix-review
description: Apply fixes from review findings with conflict-safe fixup commits
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

Apply fixes from `/review-branch` findings passed in `$ARGUMENTS`.

## Process

1. Parse findings from arguments (BLOCKING and NIT items with file:line references)
2. Address all BLOCKING issues first, then NIT items only after user confirms

### For each BLOCKING issue:

#### Step 1: Identify the target commit

Find the commit that introduced the issue:
```bash
git log --oneline origin/main..HEAD -- <file>
```

#### Step 2: Conflict prevention check

Before creating a fixup, verify the fix will not conflict during autosquash:

1. Read the target commit's diff for the file: `git show <hash> -- <file>`
2. Verify the issue exists in lines modified by the target commit
3. Check if later commits also modified the same lines:
   ```bash
   git log --oneline <hash>..HEAD -- <file>
   ```
   If later commits touched the same lines, fixup the **latest** commit that modified those lines instead of the original
4. If no commit cleanly owns the lines, create a standalone commit instead of a fixup

#### Step 3: Apply minimal fix

- Read the file and understand the problem
- Apply the minimal fix for this specific finding
- Do NOT introduce new changes unrelated to the finding
- Stage only the fixed file

#### Step 4: Verify staged changes

1. Run `git diff --cached` and confirm the staged changes only touch sections relevant to the finding
2. Run `nix flake check`

#### Step 5: Create fixup commit

```bash
git commit --fixup=<target-hash>
```

If conflict was unavoidable in step 2, create a standalone commit instead:
```bash
git commit -m "module: Fix description"
```

### After all BLOCKING issues are fixed

Show a summary of all fixes applied:
```
## Fixes Applied

fixup! <target-msg> -- fixed <description>
fixup! <target-msg> -- fixed <description>
standalone: <msg> -- <description> (conflict avoidance)
```

Then ask user if NIT items should be addressed.

## Rules

- One logical fix per fixup commit
- Never batch unrelated fixes into a single commit
- Never auto-fix NITs without user confirmation
- Never introduce changes beyond what the finding requires
- Follow commit rules from `CLAUDE.md`
- NEVER push to remote
- NEVER skip `nix flake check`

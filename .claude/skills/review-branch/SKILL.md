---
name: review-branch
description: Review all branch changes against origin/main for correctness and patterns
allowed-tools: Bash, Read, Grep, Glob, Skill, Task, WebSearch, WebFetch
---

Review all commits on the current branch compared to origin/main.

## Process

1. **Get branch overview**: Run `git log --oneline origin/main..HEAD` and `git diff origin/main...HEAD --stat`
2. **Read the full diff**: Run `git diff origin/main...HEAD` to see all changes
3. **Read modified files**: For non-trivial changes, read full files for context
4. **For Nix code**: Use `/nix-dev` skill to evaluate expressions and verify options
5. **Verify builds**: Run `nix flake check`
6. **Report findings**: Group by file or feature with file:line references

## Review Checklist

**General:**
- [ ] Code does what commit messages claim
- [ ] No obvious bugs or logic errors
- [ ] Error handling is appropriate
- [ ] No security issues introduced
- [ ] No hardcoded values that should be configurable
- [ ] No stale references after renames

**Nix-specific:**
- [ ] Module follows established patterns
- [ ] Options use appropriate types
- [ ] `lib.mkIf` used for conditional config
- [ ] Services bind to 127.0.0.1 by default
- [ ] Secrets use agenix, not plaintext
- [ ] `nix flake check` passes

**Branch hygiene:**
- [ ] Commits are logically grouped
- [ ] No unrelated changes mixed together
- [ ] Fixup commits reference correct targets

## Reporting Format

```
## Branch Review: <branch-name>

### Commits
- List of commits reviewed

### Issues
- file.nix:42 - Issue description
- file.nix:58 - Another issue

### Suggestions
- Optional improvement idea

### Verified
- nix flake check passes
- Tested with nix eval (if applicable)
```

## Rules

- Review ALL commits on the branch, not just the latest
- Use `/nix-dev` for Nix expression evaluation when needed
- Reference specific lines when reporting issues
- Distinguish blocking issues from suggestions
- Run `nix flake check` for any Nix changes
- Use `Task` agents for heavy exploration to save context

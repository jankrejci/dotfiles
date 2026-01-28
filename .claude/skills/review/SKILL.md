---
name: review
description: Review code changes for correctness, patterns, and best practices
allowed-tools: Bash, Read, Grep, Glob, Skill
---

Review code changes for correctness, idiomatic patterns, and potential issues.

## Process

1. **Understand the change**: Run `git diff` and read modified files
2. **Check correctness**: Verify logic, types, and behavior
3. **For Nix code**: Use `/nix-dev` skill to evaluate expressions and verify options
4. **Verify builds**: Run `nix flake check` for Nix changes
5. **Report findings**: List issues with file:line references

## Review Checklist

**General:**
- [ ] Code does what it claims to do
- [ ] No obvious bugs or logic errors
- [ ] Error handling is appropriate
- [ ] No security issues introduced

**Nix-specific:**
- [ ] Module follows established patterns
- [ ] Options use appropriate types
- [ ] `lib.mkIf` used for conditional config
- [ ] Services bind to 127.0.0.1 by default
- [ ] Secrets use agenix, not plaintext
- [ ] `nix flake check` passes

**Style:**
- [ ] Follows existing codebase patterns
- [ ] No unnecessary complexity
- [ ] Comments explain why, not what

## Reporting Format

```
## Review: <file or feature>

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

- Use `/nix-dev` for Nix expression evaluation
- Reference specific lines when reporting issues
- Distinguish errors from style suggestions
- Run `nix flake check` for any Nix changes

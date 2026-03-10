---
name: review-branch
description: Deep review of all branch changes against origin/main — code, commits, and CI readiness
context: fork
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Skill, Task, WebSearch, WebFetch
---

Deep, exhaustive review of all commits on the current branch compared to origin/main. The goal is that after all findings are fixed, the branch is merge-ready and all pipeline checks will pass. Do not leave anything for a second pass — find everything in one review.

## Process

### Phase 1: Gather context

1. `git log --oneline origin/main..HEAD` — list all commits
2. `git diff origin/main...HEAD --stat` — see which files changed
3. `git diff origin/main...HEAD` — full diff of all changes
4. For non-trivial changes, read full files for context beyond the diff

### Phase 2: Run all checks

Run every check that CI would run. Report failures as BLOCKING findings.

- `nix flake check` — evaluates all configurations and runs formatter check
- `nix fmt -- --check` — formatting

For Nix code, use `/nix-dev` skill to evaluate expressions and verify options when needed.

If a check cannot run, note this explicitly rather than silently skipping it.

### Phase 3: Review commit messages

For each commit, verify against CLAUDE.md commit format rules:
- Title: module prefix, imperative verb, high-level summary
- Body explains WHY the change was needed, not WHAT changed in the code
- Body does NOT enumerate code changes the reviewer can see in the diff
- One logical change per commit
- AI/tooling config not bundled with code changes
- No Co-Authored-By, no AI signatures, no emojis

### Phase 4: Review code

Evaluate against `CLAUDE.md` principles.

General:
- Correctness: logic errors, off-by-one, race conditions, missing error handling
- Security: injection, secrets in code, services exposed beyond localhost
- Consistency: follows existing patterns in the codebase
- Dead code: unused imports, unreachable branches, commented-out code
- Duplication: same content defined in multiple places (single source of truth)
- No stale references after renames

Nix-specific:
- Module follows established patterns (homelab.X.enable, option types, mkIf)
- Options use appropriate types
- Services bind to 127.0.0.1 by default
- Secrets use agenix, not plaintext
- No hardcoded values that should be configurable

### Phase 5: Cross-cutting concerns

- Are new files/modules properly integrated (imports, default.nix)?
- Do cross-host references use `config.homelab.hosts` pattern?
- Are firewall rules, nginx configs, and systemd units consistent?
- Do port/IP allocations avoid conflicts?

## Output Format

```
## Review: <branch-name> (<N> commits)

### Check Results

nix flake check: PASS/FAIL
nix fmt --check: PASS/FAIL

### Findings

BLOCKING file.nix:42 -- Description of the issue
BLOCKING file.nix:58 -- Description of the issue

NIT file.nix:100 -- Description of the issue
```

Severity levels:
- `BLOCKING` — Must fix before merge: bugs, build failures, lint errors, format violations, rule violations, incorrect commit messages
- `NIT` — Optional improvement, style preference, take it or leave it

If no issues are found, output: `No issues found. Branch is merge-ready.`

## Rules

- Review ALL commits on the branch, not just the latest
- Run ALL checks — do not skip any. If a check cannot run, report why.
- Every finding MUST include a file:line reference (or commit hash for commit message issues)
- Findings must be exhaustive: if this review passes, the branch is ready to merge
- No praise, no "looks good" summaries, no filler text
- No suggestions without file:line references
- Report only concrete issues found in the actual code or checks
- Do not invent issues that are not evidenced by code, diffs, or check output
- Use `Task` agents for heavy exploration to save context

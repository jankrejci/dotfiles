---
name: review-branch
description: Deep review of all branch changes against the review base (origin/main, or a stacked base via branch.<name>.reviewBase) — code, commits, and CI readiness
context: fork
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Skill, Task, WebSearch, WebFetch
---

Deep, exhaustive review of all commits on the current branch compared to its review base (`origin/main` by default, or a stacked base configured via `branch.<name>.reviewBase`; see Phase 1). The goal is that after all findings are fixed, the branch is merge-ready and all pipeline checks will pass. Do not leave anything for a second pass — find everything in one review.

## Process

### Phase 1: Gather context

0. Resolve the review base. The branch may be stacked on another branch
   rather than `main`, so do not assume `origin/main`:

   ```bash
   BASE=$(git config "branch.$(git branch --show-current).reviewBase" || echo origin/main)
   ```

   Report which base was resolved. To stack a branch, set its base once:
   `git config branch.<name>.reviewBase <base-ref>`.

1. `git log --oneline "$BASE"..HEAD` — list all commits
2. `git diff "$BASE"...HEAD --stat` — see which files changed
3. `git diff "$BASE"...HEAD` — full diff of all changes
4. For non-trivial changes, read full files for context beyond the diff

### Phase 2: Run all checks

First decide whether the flake check applies. A diff that touches only
harness or documentation config (`.claude/`, `*.md`, `.gitlint*`) feeds
into no Nix evaluation, so running the check would rebuild everything
without validating any of the change under review.

```bash
git diff --name-only "$BASE"...HEAD |
  grep -qvE '^\.claude/|(^|/)[^/]*\.md$|^\.gitlint' \
  && FLAKE_RELEVANT=1 || FLAKE_RELEVANT=0
```

`grep -qv` succeeds when any changed file falls outside the inert set, so
any unexpected path forces the check on; only an all-inert diff skips it.
When `FLAKE_RELEVANT=0`, skip the check and record
`nix flake check: SKIPPED (only harness/docs changed)` in the output,
then move to Phase 3.

When `FLAKE_RELEVANT=1`, run every check CI would run:

- `nix flake check` — evaluates all configurations and runs the formatter check
- `nix fmt -- --check .` — formatting; the trailing `.` is required because
  alejandra reads from stdin when given no path and then falsely reports exit 1

`nix flake check` can outlast a single tool call, so it must run
detached — but **do not** delegate it to a `Task` subagent and **do not**
poll a log for a completion sentinel. Both have failed before: a subagent
launches the check in the background and returns before it finishes,
reporting no result; and a hand-rolled `until grep …; do sleep; done`
waiter spins indefinitely whenever its sentinel never lands in the file
it polls.

Instead run it yourself as one background `Bash` call. `2>&1` is a
redirection, not a pipe, so `$?` is nix's own exit status — capture it on
the last line:

```bash
nix flake check 2>&1; echo "FLAKE_CHECK_EXIT=$?"
```

Launch it with `run_in_background: true`, then continue with Phases 3-5.
The harness re-invokes you when the command exits — wait for that
notification; never arm a separate poll loop. PASS iff the last line is
`FLAKE_CHECK_EXIT=0`, otherwise FAIL with the failing check names and the
relevant error lines. Do not emit the final report until this exit line
is in hand.

For Nix code, use `/nix-dev` skill to evaluate expressions and verify
options when needed.

If a check cannot run for a reason other than the inert-diff skip, note
this explicitly rather than silently skipping it.

### Phase 3: Per-commit review

For each commit, verify against CLAUDE.md commit format rules:
- Title: module prefix, imperative verb, high-level summary
- Body explains WHY the change was needed, not WHAT changed in the code
- Body does NOT enumerate code changes the reviewer can see in the diff
- One logical change per commit
- Lock files (flake.lock) not bundled with source changes
- AI/tooling config not bundled with code changes
- No unrelated changes smuggled in
- No Co-Authored-By, no AI signatures, no emojis

**Diff-vs-body verification:**
- Every claim in the commit body matches the actual diff
- No diff content missing from the body description
- No body claims that are not evidenced by the diff

### Phase 4: Code correctness

Review the full diff (`git diff "$BASE"...HEAD`) for:

**Logic and safety:**
- Logic errors, off-by-one, race conditions
- Missing error handling at system boundaries
- Security: injection, secrets in code, services exposed beyond localhost
- Edge cases and failure modes

**Nix-specific:**
- Module follows established patterns (homelab.X.enable, option types, mkIf)
- Options use appropriate types
- Services bind to 127.0.0.1 by default
- Secrets use agenix, not plaintext
- No hardcoded values that should be configurable

### Phase 5: Style and cross-cutting

**CLAUDE.md compliance:**
- Guard clauses over nested if-else
- Comments are proper sentences, no parenthetical asides, no size claims
- `local -r` for immutable locals in shell scripts
- Port options named `port` or `port.<name>` with `lib.types.port`

**Codebase patterns:**
- Follows existing patterns in the codebase
- Dead code: unused imports, unreachable branches, commented-out code
- Duplication: same content defined in multiple places
- No stale references after renames

**Integration:**
- New files/modules properly integrated (imports, default.nix)
- Cross-host references use `config.homelab.hosts` pattern
- Firewall rules, nginx configs, and systemd units consistent
- Port/IP allocations avoid conflicts

### Phase 6: Verification checklist

Before producing output, verify every category was checked. For each item below, confirm it was evaluated for every commit and every changed file. If any item was skipped or only partially checked, go back and complete the relevant phase before continuing.

- [ ] Flake check exit line (`FLAKE_CHECK_EXIT=`) in hand, or was skipped with reason (Phase 2)
- [ ] Every commit message verified against its diff (Phase 3)
- [ ] Every commit is a single logical change (Phase 3)
- [ ] No bundled unrelated changes (Phase 3)
- [ ] Logic errors and edge cases checked (Phase 4)
- [ ] Security reviewed (Phase 4)
- [ ] Nix patterns verified (Phase 4)
- [ ] CLAUDE.md style rules checked (Phase 5)
- [ ] Cross-cutting integration verified (Phase 5)
- [ ] No stale references from renames (Phase 5)

Only produce the final output after all items are confirmed.

## Output Format

```
## Review: <branch-name> (<N> commits)

### Check Results

nix flake check: PASS/FAIL/SKIPPED
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
- Run `nix flake check` as one background `Bash` call whenever the diff has non-inert files; never delegate it to a `Task` subagent or poll a sentinel. Skip only when Phase 2 detection shows an all-inert diff, and record the skip in the output. If a check cannot run for any other reason, report why.
- Every finding MUST include a file:line reference (or commit hash for commit message issues)
- Findings must be exhaustive: if this review passes, the branch is ready to merge
- No praise, no "looks good" summaries, no filler text
- No suggestions without file:line references
- Report only concrete issues found in the actual code or checks
- Do not invent issues that are not evidenced by code, diffs, or check output
- Use `Task` agents for heavy exploration to save context

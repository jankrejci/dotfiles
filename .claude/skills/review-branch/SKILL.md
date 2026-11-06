---
name: review-branch
description: Deep review of all branch changes against the review base (origin/main, or a stacked base via branch.<name>.reviewBase) — code, commits, and CI readiness
context: fork
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Skill, Task, WebSearch, WebFetch
---

Deep, exhaustive review of all commits on the current branch compared to its review base (`origin/main` by default, or a stacked base configured via `branch.<name>.reviewBase`; see Phase 1). The goal is that after all Important findings are fixed, the branch is merge-ready and all pipeline checks will pass. Do not leave an Important finding for a second pass.

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

Always run gitlint, whatever the diff touches, because it judges the commit
messages and not the tree. It skips fixup commits, so it stays usable mid-branch:

```bash
nix run nixpkgs#gitlint -- --commits "$BASE"..HEAD
```

Then decide whether the full flake check applies. A diff that touches only
harness or documentation config (`.claude/`, `*.md`, `.gitlint*`) feeds
into no NixOS configuration, so the full check would rebuild everything
while only the instruction checks can judge the change under review.

```bash
git diff --name-only "$BASE"...HEAD |
  command grep -qvE '^\.claude/|(^|/)[^/]*\.md$|^\.gitlint' \
  && FLAKE_RELEVANT=1 || FLAKE_RELEVANT=0
```

`grep -qv` succeeds when any changed file falls outside the inert set, so
any unexpected path forces the check on; only an all-inert diff skips it.

`command grep` bypasses a shell function named `grep`. The Claude Code
harness defines one that wraps ugrep, and it does not filter stdin the same
way, so the plain call reports an all-inert diff even when Nix files changed.

When `FLAKE_RELEVANT=0`, skip the full check, run only the instruction checks
below, and record `nix flake check: SKIPPED (only harness/docs changed)` plus
their result in the output, then move to Phase 3:

```bash
nix build --no-link .#checks.x86_64-linux.instruction-paths .#checks.x86_64-linux.claude-md-limit
```

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
- [ ] gitlint result in hand (Phase 2)
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

### Phase 7: Save the report

Save the final report, with the base and the reviewed commit above it, for
`/fix-review` to read:

```bash
{ echo "base: $BASE"; echo "head: $(git rev-parse HEAD)"; cat <<'REPORT'; } > "$(git rev-parse --absolute-git-dir)/review-branch.md"
<the report>
REPORT
```

A report held only in context is gone after compaction or in a new session.
The per-worktree git directory keeps one report per branch checkout, and
`git status` does not see it, so it cannot dirty the tree.

## Output Format

```
## Review: <branch-name> (<N> commits)

### Check Results

nix flake check: PASS/FAIL/SKIPPED
nix fmt --check: PASS/FAIL
gitlint: PASS/<its lines>

### Findings

2 important, 1 nit, 1 pre-existing

#### Important
1. CODE file.nix:42 -- Description of the issue
2. COMMITS abc1234 -- Description of the issue

#### Nit
1. DESIGN file.nix:100 -- Description of the issue

#### Pre-existing
1. CODE file.nix:7 -- Description of the issue
```

Number findings from 1 under each heading, so a reply can cite one by number. Omit a heading with nothing under it.

Severity levels:
- **Important**: breaks behaviour, leaks data, or fails a check, or a commit message claim that the diff contradicts. Must be fixed before merge
- **Nit**: anything else. Report at most five; past that, give a count and one line on what the rest were about
- **Pre-existing**: a bug this branch did not introduce. It does not count against the branch and gets its own branch

Labels say where to look: `CODE` for logic and runtime behaviour, `DESIGN` for structure, `BUILD` for what a check would fail, `DOCS` for prose and comments, `COMMITS` for history.

Close with `Merge-ready.` when the checks pass and there is no Important finding. The bar is the severity and not zero findings, because a review re-reading settled code always has something to say.

## Rules

- Review ALL commits on the branch, not just the latest
- A claim about behaviour needs a `file:line` that you read and that shows it, not an inference from a name. When a subagent reports a finding, open the cited line before repeating it, or say that you did not
- Do not report what a check already enforces: formatting, commit message format, a stale path in an instruction file, the length of `CLAUDE.md`
- Run `nix flake check` as one background `Bash` call whenever the diff has non-inert files; never delegate it to a `Task` subagent or poll a sentinel. Skip only when Phase 2 detection shows an all-inert diff, and record the skip in the output. If a check cannot run for any other reason, report why.
- Every finding MUST include a file:line reference (or commit hash for commit message issues)
- Important findings must be exhaustive: if this review reports none, the branch is ready to merge
- No praise, no "looks good" summaries, no filler text
- No suggestions without file:line references
- Report only concrete issues found in the actual code or checks
- Do not invent issues that are not evidenced by code, diffs, or check output
- Use `Task` agents for heavy exploration to save context

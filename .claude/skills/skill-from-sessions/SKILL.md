---
name: skill-from-sessions
description: Finds instructions the user keeps repeating across Claude Code sessions in this project and drafts skills or rules from them. Runs only when invoked.
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
---

An instruction typed a second time should already have been written down. Find
those and propose where each one belongs.

## Gather

Run the script beside this file, with the look-back in days, 14 by default:

```bash
bash .claude/skills/skill-from-sessions/user-messages.sh 30
```

Read the whole output before judging. Most lines are one-off task content.

## Judge

A candidate is guidance rather than a task:

- the same instruction in two or more sessions, in any wording
- a correction given twice, because the first one did not stick anywhere durable
- a pasted block of commands or a checklist that appears more than once

Drop anything already covered by `CLAUDE.md`, `.claude/rules/` or an existing
skill, unless it keeps recurring despite that. That means the existing text is
not working, which is a finding of its own.

## Propose

Pick the smallest home for each candidate:

- a sentence in an existing skill or rule, when one already covers the area
- a path-scoped file in `.claude/rules/`, when it applies to certain files
- a new skill in `.claude/skills/`, when it is a procedure someone invokes
- `CLAUDE.md`, only when every session needs it, because its length is capped

For each one, show the draft and the evidence: which sessions, and what was
repeated. Then stop. The user decides what gets written, so this skill changes
no file.

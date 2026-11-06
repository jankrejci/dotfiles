#!/usr/bin/env bash
# Prints what the user typed in this project's Claude Code sessions, one line
# per message with its session and timestamp. Assistant output, tool results and
# harness wrappers are dropped, because a repeated instruction is the signal and
# the rest would bury it. The optional argument is the look-back in days.
set -euo pipefail

days="${1:-14}"
root="$(git rev-parse --path-format=absolute --git-common-dir)"
root="${root%/.git}"
dir="$HOME/.claude/projects/$(printf '%s' "$root" | tr '/.' '--')"

[ -d "$dir" ] || {
  echo "no transcripts at $dir" >&2
  exit 1
}

# Only top-level files are searched. Subagent transcripts sit in subdirectories,
# and the "user" messages there are prompts that a session wrote.
find "$dir" -maxdepth 1 -name '*.jsonl' -mtime "-$days" -print0 | sort -z |
  while IFS= read -r -d '' transcript; do
    jq -r --arg session "$(basename "$transcript" .jsonl)" '
      select(.type == "user" and (.isMeta | not))
      | .message.content as $content
      | (if ($content | type) == "string" then $content
         else ([$content[]? | select(.type == "text") | .text] | join(" "))
         end) as $text
      | select($text != "")
      | select($text | test("<command-name>|<local-command|<system-reminder|<task-notification>|<agent-message|<bash-|\\[Request interrupted|^Base directory for this skill:") | not)
      | "\($session[0:8]) \(.timestamp // "-") | \($text | gsub("\\s+"; " ") | .[0:400])"
    ' "$transcript" 2>/dev/null || true
  done

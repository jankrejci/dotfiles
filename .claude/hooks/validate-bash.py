#!/usr/bin/env python3
"""PreToolUse hook: Block dangerous bash commands.

Prevents execution of commands that could break connectivity, push to remote,
or cause destructive changes. Exit code 2 blocks the command and sends
stderr back to Claude.
"""

import json
import re
import sys


BLOCKED_PATTERNS = [
    (r"\bgit\s+push\b", "NEVER push to remote. User will push when ready."),
    (r"\bgit\s+push\s+--force", "Force push is forbidden."),
    (r"\bnetbird\s+down\b", "Never run netbird down while connected via VPN."),
    (r"\brm\s+-rf\s+/", "Recursive delete from root is forbidden."),
    (r"\bnixos-rebuild\s+switch\b", "Use deploy workflow instead of direct switch."),
    (r"\bgit\s+rebase\s+-i\b", "Interactive rebase requires terminal. Use non-interactive."),
    (r"\bgit\s+add\s+-i\b", "Interactive add requires terminal. Use git add -p or explicit paths."),
]


def main():
    input_data = json.load(sys.stdin)
    command = input_data.get("tool_input", {}).get("command", "")

    for pattern, message in BLOCKED_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            print(f"Blocked: {message}", file=sys.stderr)
            sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()

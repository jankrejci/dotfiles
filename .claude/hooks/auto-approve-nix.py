#!/usr/bin/env python3
"""PreToolUse hook: Auto-approve safe nix and git commands.

Skips permission prompts for read-only and safe commands defined in CLAUDE.md.
Returns JSON with permissionDecision to allow, or exits 0 to let normal flow proceed.
"""

import json
import re
import sys


SAFE_PATTERNS = [
    r"^nix\s+build\b",
    r"^nix\s+eval\b",
    r"^nix\s+flake\s+check\b",
    r"^nix\s+flake\s+show\b",
    r"^nix-store\s+--query\b",
    r"^nix\s+path-info\b",
    r"^nix\s+why-depends\b",
    r"^git\s+status\b",
    r"^git\s+diff\b",
    r"^git\s+log\b",
    r"^git\s+show\b",
    r"^nix\s+fmt\b",
]


def main():
    input_data = json.load(sys.stdin)
    command = input_data.get("tool_input", {}).get("command", "").strip()

    for pattern in SAFE_PATTERNS:
        if re.match(pattern, command):
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow",
                }
            }
            print(json.dumps(output))
            sys.exit(0)

    # Not a safe command, let normal permission flow handle it.
    sys.exit(0)


if __name__ == "__main__":
    main()

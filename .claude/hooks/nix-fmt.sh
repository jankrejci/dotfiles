#!/usr/bin/env bash
# PostToolUse hook: Auto-format .nix files after Edit/Write
#
# Runs nix fmt on modified .nix files to ensure consistent formatting.
# Exits 0 always to avoid blocking the workflow on format failures.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0
[[ "$FILE_PATH" != *.nix ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

nix fmt "$FILE_PATH" 2>/dev/null || true
exit 0

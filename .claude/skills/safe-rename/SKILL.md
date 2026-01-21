---
name: safe-rename
description: Safely find all references before renaming interfaces, ports, or service identifiers
disable-model-invocation: true
allowed-tools: Read, Grep, Glob
---

Before renaming any network interface, port, or service identifier, find all references that must be updated to avoid breaking connectivity or services.

## Arguments

$ARGUMENTS should be: `old_name` or `old_name new_name`

## Process

1. Parse arguments into OLD_NAME and optionally NEW_NAME
2. Search entire codebase for references:
   ```bash
   rg -l "$OLD_NAME" --type nix
   rg -l "$OLD_NAME" --type json
   ```
3. For each file found, show the matching lines with context:
   ```bash
   rg -n -C 2 "$OLD_NAME" <file>
   ```
4. Specifically check these high-risk locations:
   - Firewall rules: `modules/networking.nix`
   - Systemd units: `homelab/*.nix`, `modules/*.nix`
   - Nginx configs: `homelab/*.nix`
   - Port definitions: `flake/options.nix`
   - Deploy scripts: `scripts.nix`
5. Report all locations that reference OLD_NAME
6. DO NOT make any changes - only report findings
7. If NEW_NAME provided, show what each change would look like

## Output Format

```
Found N references to "old_name":

## High Risk (connectivity/firewall)
- modules/networking.nix:42 - firewall rule
- modules/netbird-homelab.nix:15 - interface name

## Service Configuration
- homelab/jellyfin.nix:78 - port reference
- homelab/grafana.nix:23 - upstream reference

## Other
- CLAUDE.md:118 - documentation
```

## Rules

- NEVER make changes automatically
- ALWAYS ask user to confirm before any edits
- If OLD_NAME appears in firewall rules, warn about connectivity risk
- If OLD_NAME is a systemd unit name, warn about dependent services
- All references must be updated atomically in a single commit

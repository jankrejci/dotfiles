---
name: new-service
description: Create a new homelab service module following project patterns
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

Create a new NixOS service module in the homelab pattern.
Follow service rules and integration patterns from CLAUDE.md.

## Arguments

Set SERVICE from the skill arguments:
```
SERVICE=$ARGUMENTS
```

The service name should be lowercase, e.g., "myservice".

## Process

1. Verify service does not exist: `ls homelab/$SERVICE.nix`
2. Read reference modules listed in CLAUDE.md "Adding a new service" section
3. Create module at `homelab/$SERVICE.nix` following the `homelab.X.enable` pattern
4. Add import to `homelab/default.nix` in alphabetical order
5. Run `nix flake check`
6. Report what files were created/modified

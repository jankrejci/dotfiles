---
name: nix-dev
description: Develop and debug Nix expressions with evaluation and build tools
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

Develop, debug, and iterate on Nix expressions.

## Capabilities

This skill provides access to Nix tooling for development work:
- `nix eval` - Evaluate Nix expressions and inspect values
- `nix build` - Build derivations
- `nix flake check` - Validate flake
- `nix flake show` - Show flake outputs
- `nix repl` - Interactive exploration (use `--expr` for non-interactive)
- `nix-instantiate` - Debug derivations

## Common Workflows

**Evaluate an expression:**
```bash
nix eval .#nixosConfigurations.hostname.config.services.nginx.enable
```

**Evaluate with JSON output:**
```bash
nix eval --json .#nixosConfigurations.hostname.config.networking.firewall.allowedTCPPorts
```

**Debug a module option:**
```bash
nix eval .#nixosConfigurations.hostname.config.homelab --apply builtins.attrNames
```

**Check derivation without building:**
```bash
nix-instantiate --eval -E 'with import <nixpkgs> {}; lib.version'
```

**Build and check:**
```bash
nix build .#nixosConfigurations.hostname.config.system.build.toplevel --dry-run
```

**Explore flake outputs:**
```bash
nix flake show --json | jq '.nixosConfigurations | keys'
```

## Debugging Tips

**Type errors:**
```bash
nix eval --show-trace .#problematic.expression
```

**Infinite recursion:**
```bash
nix eval --show-trace --option eval-max-statements 100000 .#expression
```

**Check option types:**
```bash
nix eval .#nixosConfigurations.host.options.services.nginx.enable.type.name
```

## Rules

- Use `--show-trace` when debugging errors
- Use `--json` for machine-readable output
- Prefer `nix eval` over `nix repl` for scriptable operations
- Run `nix flake check` to validate after changes

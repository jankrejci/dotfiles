---
name: deploy
description: Deploy NixOS configuration to a target host via deploy-rs
user_invocable: true
arguments: "<hostname>"
---

# Deploy Skill

Deploy NixOS configuration changes to a remote host.

## Usage

```
/deploy <hostname>
```

## Pre-Deployment Checklist

Before deploying, verify all of the following:

1. **Build passes**:
   ```bash
   nix flake check
   nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel
   ```

2. **Connectivity**:
   - Verify VPN is connected if deploying remotely
   - Test SSH access: `ssh admin@<hostname>.nb.krejci.io true`
   - NEVER run `netbird down` while SSH'd via VPN

3. **Review changes**:
   ```bash
   nix store diff-closures /run/current-system ./result
   ```

4. **Check current state**:
   ```bash
   ssh admin@<hostname>.nb.krejci.io systemctl list-units --failed
   ```

## Deployment

Use deploy-config, which wraps deploy-rs:
```bash
nix run .#deploy-config <hostname>
```

For full build logs instead of progress bar:
```bash
nix run .#deploy-config <hostname> -- -L
```

## Post-Deployment Verification

```bash
ssh admin@<hostname>.nb.krejci.io systemctl list-units --failed
ssh admin@<hostname>.nb.krejci.io systemctl status <service>
```

## Connectivity Safety

**CRITICAL: Never break your own access path**

- NEVER run `netbird down` while SSH'd via VPN
- NEVER delete VPN peer while needing remote access
- If changes affect networking: inform user, let them execute locally

Before renaming interfaces or services:
```bash
grep -r "old_name" .
```
Update ALL hardcoded references before deploying.

## Rollback

If deployment fails:
```bash
# On target host
sudo nixos-rebuild switch --rollback

# Or boot previous generation from bootloader
```

## Process

1. Run all pre-deployment checks
2. Present deployment plan to user and wait for confirmation
3. Deploy with `nix run .#deploy-config <hostname>`
4. Run post-deployment verification
5. Report results

# Dotfiles
NixOS homelab configuration using Nix flakes.

## Architecture

### Network
Hosts connect via Netbird VPN (mesh network). Services accessible at `<hostname>.<domain>` addresses.

### Hosts
Each host runs minimal NixOS configuration. Default user: `admin`.

### Desktops
Desktop machines use Nix for system packages and Flatpak for heavy applications (browsers, CAD tools).

## Prepare Installation Media

### USB installer (x86_64)
```bash
nix run .#build-installer
```
Generates ISO with ephemeral Netbird setup key. Requires `NETBIRD_API_TOKEN` environment variable. Burn to USB:
```bash
sudo dd if=./iso-image/nixos-minimal-*.iso of=/dev/sdX bs=10M oflag=dsync status=progress; sync
```
Boot target machine from USB. It connects to VPN at `iso.<domain>`.

### SD card image (aarch64 Raspberry Pi)
```bash
nix run .#build-sdcard rpi4
```
Burn to SD card:
```bash
sudo dd if=./result/rpi4-sdcard/nixos-image-*.img of=/dev/sdX bs=10M oflag=dsync status=progress; sync
```
Insert and boot. Connects to VPN automatically. Reboots once after first boot.

## Install NixOS

```bash
nix run .#nixos-install <hostname>
```
Installs NixOS remotely to target machine. Requires:
- Target booted from USB installer (accessible at `iso.<domain>`)
- Host configuration in `hosts/<hostname>/`

Example:
```bash
nix run .#nixos-install optiplex
```

## Update System

```bash
nix run .#deploy-config <hostname>
```
Builds configuration locally and deploys to running host.

Example:
```bash
nix run .#deploy-config optiplex
```

## Setup Immich Backup

1. Generate SSH key on thinkcenter:
   ```bash
   ssh-keygen -t ed25519 -f /root/.ssh/borg-backup-key -N ""
   ```

2. Add public key to `ssh-authorized-keys.conf`:
   ```
   vpsfree, borg, ssh-ed25519 AAAA... thinkcenter-backup
   ```

3. Inject passphrases and initialize repositories:
   ```bash
   # Remote backup (initializes repo on vpsfree, injects passphrase to thinkcenter)
   nix run .#inject-borg-passphrase vpsfree thinkcenter

   # Local backup (initializes repo on thinkcenter, injects passphrase to thinkcenter)
   nix run .#inject-borg-passphrase thinkcenter thinkcenter
   ```

**Verification:**
```bash
# Check repository initialized
borg list /var/lib/borg-repos/immich

# Check backup timers scheduled
systemctl list-timers | grep borg

# Test backup manually
systemctl start borgbackup-job-immich-remote
systemctl start borgbackup-job-immich-local
```

Backups run daily at midnight. Both remote (to vpsfree/NAS) and local (to NVMe) backups run simultaneously.

**Restore from backup:**
```bash
# List available backups (on thinkcenter)
restore-immich-backup

# Restore from remote backup (on thinkcenter)
restore-immich-backup remote thinkcenter-immich-2025-11-21T09:09:45

# Restore from local backup (on thinkcenter)
restore-immich-backup local thinkcenter-immich-2025-11-21T09:09:45
```


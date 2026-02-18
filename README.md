# Dotfiles

NixOS homelab configuration managing servers, desktops, and Raspberry Pis
with Nix flakes. Uses [flake-parts](https://flake.parts) for modular
organization.

## Repository Structure

```
flake.nix              # Entry point, imports ./flake via flake-parts
flake/
  default.nix          # Imports all flake submodules
  options.nix          # Flake-level and NixOS-level homelab option types
  packages.nix         # perSystem: formatter, packages, checks, overlays
  hosts.nix            # Host definitions and nixosConfigurations output
  lib.nix              # Shared module builders for hosts and images
  deploy.nix           # deploy-rs node configuration
  images.nix           # ISO and SD card image builders
homelab/               # Service modules (homelab.X.enable pattern)
modules/               # Base NixOS modules (common, ssh, networking, etc.)
hosts/                 # Per-host configuration overrides
users/                 # User configurations (admin, jkr, paja)
pkgs/                  # Custom packages
scripts/               # Deployment and utility scripts
secrets/               # agenix-rekey encrypted secrets
  rekeyed/             # Per-host rekeyed secrets
assets/                # Static assets (Grafana dashboards, templates)
wireguard-keys/        # WireGuard public keys for backup tunnel
```

## Hosts

Defined in `flake/hosts.nix`. Each host declares standard NixOS options at the
top level and service configuration under `homelab`, which maps directly to
`homelab.*` NixOS options from `homelab/*.nix` modules.

### Servers

| Host | Arch | Role |
|------|------|------|
| thinkcenter | x86_64 | Primary homelab server. Runs Grafana, Prometheus, Immich, Jellyfin, Ntfy, Memos, Dex, PostgreSQL, Redis, nginx. TPM-encrypted root + NVMe data. |
| vpsfree | x86_64 | Remote VPS on vpsadminOS. Tunnel endpoint with TLS proxy, ACME, watchdog, borg backup target. |

### Desktops

| Host | Arch | Hardware |
|------|------|----------|
| framework | x86_64 | Framework 13 AMD 7040 |
| t14 | x86_64 | Lenovo ThinkPad T14 AMD Gen1 |
| e470 | x86_64 | Lenovo ThinkPad E470 |
| optiplex | x86_64 | Dell OptiPlex |

All desktops run GNOME + Hyprland, Plymouth, TPM or password encryption,
the netbird user VPN client, and flatpak with Flathub for desktop apps
(browsers, CAD tools, slicers) that auto-update on activation.

### Raspberry Pi

| Host | Role |
|------|------|
| rpi4 | Base RPi 4 system |
| prusa | 3D printer controller (Octoprint + webcam) |
| rak2245 | LoRaWAN gateway (ChirpStack + GPS time sync) |

All RPi hosts are aarch64-linux, boot from SD card, use WiFi via iwd.

### Installer

**iso** - Custom NixOS installer with embedded SSH host key for agenix
secret decryption. Used as ephemeral install media.

## Service Modules

Located in `homelab/`. Each module follows the `homelab.X.enable` pattern with
sensible defaults. Services self-register metrics scrape targets, alert rules,
health checks, and backup jobs.

### Infrastructure
| Module | Purpose |
|--------|---------|
| nginx | TLS termination, reverse proxy, metrics exporter |
| postgresql | Shared PostgreSQL 16 instance |
| redis | Shared Redis instance |
| acme | Wildcard certificates via Cloudflare DNS-01 |

### Authentication and Monitoring
| Module | Purpose |
|--------|---------|
| dex | OIDC identity broker (Google OAuth + local passwords) |
| prometheus | Metrics collection with scrape target aggregation |
| loki | Log aggregation |
| grafana | Dashboards with Dex SSO |
| ntfy | Push notifications for alerts |
| health-check | Distributed health checks with daily ntfy digest |

### Applications
| Module | Purpose |
|--------|---------|
| immich | Photo library with Dex SSO and ML features |
| immich-public-proxy | Public share links via tunnel proxy |
| jellyfin | Media server with Dex SSO |
| memos | Note-taking app |
| octoprint | 3D printer controller with Obico monitoring |
| webcam | Camera streaming via camera-streamer |
| printer | Brother DCP-T730DW via CUPS |

### Network and Backup
| Module | Purpose |
|--------|---------|
| tunnel | Encrypted tunnel with L4 TLS proxy for public service exposure |
| backup | Borg backup to local and remote (vpsfree) targets with automatic PostgreSQL dumps, per-service restore scripts, Prometheus staleness alerts, and health checks. Retention: 7 daily, 4 weekly, 6 monthly. Remote traffic goes over a dedicated WireGuard tunnel. |
| lorawan-gateway | ChirpStack with u-blox GPS time sync |

## Base Modules

Located in `modules/`. Imported by all hosts via `modules/default.nix`.

| Module | Purpose |
|--------|---------|
| common | Nix flakes, boot, locale, base packages |
| ssh | SSH hardening and authorized keys |
| networking | systemd-networkd, systemd-resolved, metrics proxy, node exporter |
| monitoring | Monitoring option definitions |
| options | `homelab.*` NixOS option types |

### Profile Modules
| Module | Purpose |
|--------|---------|
| headless | Server packages |
| desktop | GNOME, flatpak, printing, scanning, Plymouth |
| notebook | Laptop power management |
| hyprland | Hyprland window manager |

### Network Modules
| Module | Purpose |
|--------|---------|
| netbird-homelab | System VPN client (port 51820, setup key enrollment) |
| netbird-user | User VPN client (port 51821, SSO via tray UI) |

### Disk Encryption
| Module | Purpose |
|--------|---------|
| disk-tpm-encryption | Disko + TPM2 + Secure Boot |
| disk-password-encryption | Password-only LUKS |

### Hardware
| Module | Purpose |
|--------|---------|
| raspberry | RPi base config (serial UART, WiFi, overlays) |
| vpsadminos | OpenVZ container quirks for vpsfree |

## Network Architecture

### VPN

Hosts connect via [Netbird](https://netbird.io/) mesh VPN. Two client types
cannot run simultaneously due to routing table conflicts.

- **System client** (`netbird-homelab`, port 51820) - Servers and RPi. Setup
  key enrollment, always-on system service.
- **User client** (`netbird-user`, port 51821) - Desktops. SSO login via tray
  UI, runs as systemd user service.

Services are accessible at `<service>.<domain>` via Netbird DNS. Internal
peer resolution uses `<host>.nb.<domain>`.

### Service IPs

Services get dedicated IPs on a dummy interface, routed via Netbird:

```
thinkcenter (192.168.91.x):
  .1 immich    .2 grafana   .3 jellyfin    .4 ntfy
  .5 printer   .6 memos     .7 dex         .8 prometheus
  .10 immich-public-proxy

vpsfree (192.168.92.x):
  .2 watchdog

prusa (192.168.93.x):
  .1 octoprint
```

### Defense in Depth

Services bind to localhost only. Nginx handles TLS termination. Firewall
restricts access to the VPN interface.

### Tunnel

Persistent WireGuard tunnel between thinkcenter (192.168.99.1) and vpsfree
(192.168.99.2), independent of Netbird. Used for borg backup traffic and the
L4 TLS proxy that exposes selected services to the public internet via
SNI-based routing through vpsfree.

## Secrets Management

Uses [agenix-rekey](https://github.com/oddlama/agenix-rekey) with dual master
keys (framework + t14). Either key can decrypt all secrets independently.

Secrets live in `secrets/*.age` and are rekeyed per-host into
`secrets/rekeyed/<hostname>/`. Hosts declare their `hostPubkey` in the host
definition for automatic encryption.

## Custom Packages

| Package | Purpose |
|---------|---------|
| import-keep | Import Google Keep notes to Memos |
| camera-streamer | Camera streaming for Octoprint |
| soft-uart-tx | Software UART TX for GPS on broken RPi GPIO14 |
| octoprint-obico | Remote 3D printer monitoring plugin |
| octoprint-prometheus-exporter | Metrics exporter plugin |
| netbird-ui-white-icons | White tray icon overlay |

## Usage

### Prepare Installation Media

Build USB installer ISO:
```bash
nix run .#build-installer
```

Build RPi SD card image:
```bash
nix run .#build-sdcard <hostname>
```

Write to media:
```bash
sudo dd if=./result/*.img of=/dev/sdX bs=10M oflag=dsync status=progress; sync
```

### Install NixOS

Boot target from installer media, then:
```bash
nix run .#nixos-install <hostname>
```

### Deploy Configuration

```bash
nix run .#deploy-config <hostname>
```

Builds locally and deploys to the running host via VPN.

### Other Scripts

| Script | Purpose |
|--------|---------|
| `add-ssh-key` | Add SSH keys to `ssh-authorized-keys.conf` |
| `reenroll-netbird` | Re-enroll Netbird client with new setup key |
| `inject-borg-passphrase` | Deploy borg passphrase and initialize backup repo |

### Setup Borg Backup

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
   nix run .#inject-borg-passphrase vpsfree thinkcenter   # remote
   nix run .#inject-borg-passphrase thinkcenter thinkcenter # local
   ```

4. Verify:
   ```bash
   systemctl list-timers | grep borg
   systemctl start borgbackup-job-immich-remote
   ```

Restore:
```bash
restore-immich-backup remote thinkcenter-immich-2025-11-21T09:09:45
```

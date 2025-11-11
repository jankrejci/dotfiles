# Dotfiles
NixOS homelab configuration using Nix flakes.

## Architecture

### Network
Hosts connect via Netbird VPN (mesh network). Services accessible at `<hostname>.x.nb` addresses.

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
Boot target machine from USB. It connects to VPN at `iso.x.nb`.

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
- Target booted from USB installer (accessible at `iso.x.nb`)
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


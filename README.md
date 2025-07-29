# Dotfiles
NixOS system defined through flake.

## Bootable images

### USB stick for x86_64 targets 

When you boot from this stick, host connects over the VPN and is prepared to be installed.

### SD card for aarch64 raspberries

Insert SD card and wait for boot, now everything works out of the box! It restarts after the first boot, so the first start takes a bit longer.

## Installation

## Update

## Handy scripts

### build-installer
```
nix run .#build-installer
```
Builds iso file, that can be burned on USB flash with
```
sudo dd if=./result/iso-image/nixos-minimal-...-linux.iso of=/dev/sdX bs=10MB oflag=dsync status=progress; sync
```
This USB stick can be used to boot x86-64 machine and NixOS can be istalled trhough it.
Every time the script is invoked, new wireguard key pair is generated. The reason is to avoid storing
the private key anywhere. Therefore you need to push the change and rebuild VPN server with updated public key.

### build-sdcard
```
nix run .#build-sdcard rpi4
```
Builds image, that can be burned on sdcard
```
sudo dd if=./result/rpi4-sdcard/nixos-image-...-linux.img of=/dev/sdX bs=10MB oflag=dsync status=progress; sync
```
This sdcard can be used to boot aarch64 Raspberry Pi machine and NixOS can be istalled trhough it.
Every time the script is invoked, new wireguard key pair is generated. The reason is to avoid storing
the private key anywhere. Therefore you need to push the change and rebuild VPN server with updated public key.

### generate-ssh-key

### wireguard-config

### deploy-config

### nixos-install

```
nix run .#nixos-install optiplex
```
You can install NixOS system using this script. It expects running Linux system reachable on iso.vpn.
This can be achieved through booting the machine from USB stick prepared with `build-installer`

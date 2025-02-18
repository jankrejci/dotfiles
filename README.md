# Description
Working environment defined with Nix and home-manager

# Host installation
## Generic x86_64 targets
Generate installation ISO image 
```nix
LOAD_KEYS=1 nix build .#image.iso --impure
```
Create installation USB stick
```shell
sudo dd if=./result/iso/nisox-installer.img of=/dev/sdX bs=10MB oflag=dsync status=progress; sync
```
When you boot from this stick, host connects over the VPN and is prepared to be installed.

## Raspberry aarch64 targets
Generate installation SD card image. 
```nix
LOAD_KEYS=1 nix build .#image.rpi4 --impure
```
Create installation USB stick
```shell
sudo dd if=./result/sd-image/rpi4.img of=/dev/sdX bs=10MB oflag=dsync status=progress; sync
```
Insert SD card and wait for boot, now everything works out of the box! It restarts after the first boot, so the first start takes a bit longer.

## Legacy way
Install nix through the [nix-installer](https://github.com/DeterminateSystems/nix-installer)
```shell
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
Or download the nixos image from the [nixos.org](https://nixos.org/download/) and create bootable flash
```
sudo dd bs=4M conv=fsync oflag=direct status=progress if=<path-to-image> of=/dev/sdX
```

# Key management
All private keys are stored in `./secrets.yaml` encrypted with "admin" age keys. 

## Generate host specific secrets
Out of the shared `secrets.yaml`, host secrets are generated using the `sops/.#host` flake. It generates host specific secrets stored in `hosts/<hostname>/secrets.yaml`, encrypted with "admin" keys and also with the host key.
```nix
nix run sops/.#host rpi4 --impure
```
## Generate sops configuration
```nix
nix run sops/.#config --impure
```
## Generate image with host age key included
Host age key is injected into installation image during the build process if the `LOAD_KEYS=1` environment variable is set. 
```nix
LOAD_KEYS=1 nix build .#image.rpi4 --impure
```


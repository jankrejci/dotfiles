# Description

Working environment defined with Nix and home-manager

# Installation

Install nix through the [nix-installer](https://github.com/DeterminateSystems/nix-installer)
```shell
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
Or download the nixos image from the [nixos.org](https://nixos.org/download/) and create bootable flash
```
sudo dd bs=4M conv=fsync oflag=direct status=progress if=<path-to-image> of=/dev/sdX
```

# Update packages
Update package versions in flake.lock
```shell
cd ~/dotfiles; nix flake update
```
Install updated packages
```shell
sudo nixos-rebuild switch --flake .#optiplex
```
Cleanup unused packages from nix store
```shell
nix-store --gc
```

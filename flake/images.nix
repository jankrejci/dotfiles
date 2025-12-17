# Installer ISO and SD card images
{
  inputs,
  config,
  withSystem,
  ...
}: let
  lib = inputs.nixpkgs.lib;
  hosts = config.flake.hosts;
  global = config.flake.global;
  services = config.flake.services;
  nixosHosts = lib.filterAttrs (_: h: (h.kind or "nixos") == "nixos") hosts;
  rpiHosts = lib.filterAttrs (_: h: h.isRpi or false) nixosHosts;

  # Common base modules
  baseModules = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.nix-flatpak.nixosModules.nix-flatpak
    ../modules # Base system modules
    ../homelab # Service modules with enable pattern
    ../users/admin.nix
  ];

  # Create modules list for a host
  mkModulesList = {
    hostName,
    host,
    additionalModules ? [],
  }: let
    hostConfigFile = ../hosts/${hostName}.nix;
    hasHostConfig = builtins.pathExists hostConfigFile;
  in
    baseModules
    ++ lib.optional hasHostConfig hostConfigFile
    ++ host.extraModules or []
    ++ additionalModules
    ++ [
      # Inject shared homelab configuration
      ({...}: {
        # Current host metadata for modules that need device, swapSize, etc.
        # Excludes homelab key - use config.homelab.X for service config instead.
        homelab.host = (builtins.removeAttrs host ["homelab"]) // {hostName = host.hostName or hostName;};
        # All hosts for cross-host references like wireguard peers
        homelab.hosts = hosts;
        # Global config: domain, peerDomain
        homelab.global = global;
        # Shared service config: https.port, metrics.port, netbird.*
        homelab.services = services;
      })
      # Inject host-specific homelab config directly into NixOS module system.
      # The attrset merges with option definitions from ../homelab/*.nix modules.
      ({...}: {homelab = host.homelab or {};})
    ];

  # Cached aarch64 packages for RPi overlay
  cachedPkgs-aarch64 = import inputs.nixpkgs {
    system = "aarch64-linux";
    config.allowUnfree = true;
  };
in {
  flake.image = {
    # USB stick installer ISO
    installer = withSystem "x86_64-linux" ({pkgs, ...}: let
      installerSystem = lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules =
          mkModulesList {
            hostName = "iso";
            host = hosts.iso;
            additionalModules = [
              "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ../modules/netbird-homelab.nix
              ../modules/load-keys.nix
              ({...}: {
                isoImage.makeEfiBootable = true;
                isoImage.makeUsbBootable = true;
                isoImage.compressImage = false;
              })
            ];
          }
          ++ [({...}: {nixpkgs.pkgs = pkgs;})];
      };
    in
      installerSystem.config.system.build.isoImage);

    # SD card images for Raspberry Pi
    sdcard = lib.genAttrs (builtins.attrNames rpiHosts) (hostName: let
      host = hosts.${hostName};
    in
      (inputs.nixos-raspberrypi.lib.nixosSystem {
        specialArgs = {
          inherit inputs cachedPkgs-aarch64;
          inherit (inputs) nixos-raspberrypi;
        };
        modules =
          mkModulesList {inherit hostName host;}
          ++ [
            inputs.nixos-raspberrypi.nixosModules.sd-image
            ../modules/load-keys.nix
            ../modules/load-wifi.nix
            ({lib, ...}: {
              sdImage.compressImage = false;
              sdImage.firmwareSize = lib.mkForce 256;
            })
          ];
      })
      .config
      .system
      .build
      .sdImage);
  };
}

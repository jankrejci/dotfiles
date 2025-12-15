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

  # Common base modules - use single import point
  baseModules = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.nix-flatpak.nixosModules.nix-flatpak
    ../modules # Single import for all homelab modules
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
      # Inject homelab configuration
      ({...}: {
        homelab.host = host // {hostName = host.hostName or hostName;};
        homelab.hosts = hosts;
        homelab.global = global;
        homelab.services = services;

        # Wire up enable flags
        homelab.immich.enable = host.modules.immich.enable or false;
        homelab.grafana.enable = host.modules.grafana.enable or false;
        homelab.prometheus.enable = host.modules.prometheus.enable or false;
        homelab.ntfy.enable = host.modules.ntfy.enable or false;
        homelab.octoprint.enable = host.modules.octoprint.enable or false;
      })
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

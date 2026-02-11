# Installer ISO and SD card images
{
  inputs,
  config,
  withSystem,
  ...
}: let
  lib = inputs.nixpkgs.lib;
  hosts = config.flake.hosts;
  shared = import ./lib.nix {
    inherit inputs lib hosts;
    inherit (config.flake) global services;
  };
  nixosHosts = lib.filterAttrs (_: h: (h.kind or "nixos") == "nixos") hosts;
  rpiHosts = lib.filterAttrs (_: h: h.isRpi or false) nixosHosts;

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
        specialArgs = {
          inherit inputs;
        };
        modules =
          shared.baseModules
          ++ shared.mkModulesList {
            hostName = "iso";
            host = hosts.iso;
            additionalModules = [
              "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ../modules/netbird-homelab.nix
              ../modules/load-keys.nix
              ({...}: let
                # ISO_HOST_KEY is set by build-installer script after decrypting
                # secrets/iso-host-key.age with the master key
                isoHostKey = builtins.getEnv "ISO_HOST_KEY";
              in {
                isoImage.makeEfiBootable = true;
                isoImage.makeUsbBootable = true;
                isoImage.compressImage = false;

                # Embed host key for agenix secret decryption at runtime
                environment.etc."ssh/ssh_host_ed25519_key" = {
                  text = isoHostKey;
                  mode = "0600";
                };
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
          shared.baseModules
          ++ shared.mkModulesList {inherit hostName host;}
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

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

    # SD card images for Raspberry Pi. The image extends the host's deployed
    # configuration instead of assembling its own module list, which had
    # drifted from mkRpiSystem and lost the unstable overlay, raspberry.nix
    # and the nixpkgs pinned by nixos-raspberrypi.
    sdcard = lib.genAttrs (builtins.attrNames rpiHosts) (hostName:
      (inputs.self.nixosConfigurations.${hostName}.extendModules {
        modules = [
          inputs.nixos-raspberrypi.nixosModules.sd-image
          ../modules/load-keys.nix
          ../modules/load-wifi.nix
          ({
            config,
            lib,
            ...
          }: {
            sdImage.compressImage = false;
            # Under U-Boot the kernels live on the root partition, so the
            # firmware partition only holds the firmware itself. The kernel
            # bootloader keeps every generation's kernel and initrd there, so
            # it keeps the upstream size.
            sdImage.firmwareSize =
              lib.mkIf (config.boot.loader.raspberry-pi.bootloader == "uboot")
              (lib.mkForce 256);
          })
          ({
            config,
            lib,
            pkgs,
            modulesPath,
            ...
          }:
            lib.mkIf (config.homelab.host.filesystem == "btrfs") {
              sdImage.rootFilesystemCreator = modulesPath + "/../lib/make-btrfs-fs.nix";
              # The sd-image module hardcodes ext4 for the root it builds.
              fileSystems."/".fsType = lib.mkForce "btrfs";
              # Upstream grows the root with resize2fs, which only handles
              # ext4. The partition step is kept and the mounted filesystem is
              # grown with btrfs instead.
              systemd.services.expand-root-partition.script = lib.mkForce ''
                rootPart=$(${lib.getExe' pkgs.util-linux "findmnt"} -nvo SOURCE /)
                bootDevice=$(${lib.getExe' pkgs.util-linux "lsblk"} -npo PKNAME $rootPart)
                partNum=$(${lib.getExe' pkgs.util-linux "lsblk"} -npo MAJ:MIN $rootPart | ${lib.getExe pkgs.gawk} -F: '{print $2}')

                echo ",+," | ${lib.getExe' pkgs.util-linux "sfdisk"} -N$partNum --no-reread $bootDevice
                ${lib.getExe' pkgs.parted "partprobe"}
                ${lib.getExe' pkgs.btrfs-progs "btrfs"} filesystem resize max /
              '';
            })
        ];
      })
      .config
      .system
      .build
      .sdImage);
  };
}

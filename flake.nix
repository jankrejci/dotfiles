{
  description = "NixOS multi host configuration";

  # Binary cache for nixos-raspberrypi packages like ffmpeg-headless and kernel.
  # Applies to all nix commands including nix build and nix eval.
  nixConfig = {
    extra-substituters = ["https://nixos-raspberrypi.cachix.org"];
    extra-trusted-public-keys = ["nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="];
  };

  inputs = {
    # Most of packages are fetched from the stable channel
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    # Some bleeding edge packages are fetch from unstable
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # A collection of NixOS modules covering hardware quirks
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # Manage a user environment
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # For accessing `deploy-rs`'s utility Nix functions
    deploy-rs.url = "github:serokell/deploy-rs";
    # nixgl is needed for alacritty outside of nixOS
    # refer to https://github.com/NixOS/nixpkgs/issues/122671
    # https://github.com/guibou/nixGL/#use-an-overlay
    nixgl.url = "github:guibou/nixGL";
    # Declarative partitioning and formatting
    disko.url = "github:nix-community/disko";
    # Install NixOS everywhere via SSH
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    # Raspberry Pi NixOS support with RPi kernel and proper config.txt generation.
    # Using main branch to match binary cache which is built from latest.
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    nixos-hardware,
    home-manager,
    deploy-rs,
    nixgl,
    disko,
    nixos-anywhere,
    nix-flatpak,
    nixos-raspberrypi,
    ...
  } @ inputs: let
    lib = nixpkgs.lib;

    # Two version of packages are declared both for x86_64 and aarch64 hosts
    unstable-x86_64-linux = final: _prev: {
      unstable = import nixpkgs-unstable {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
    };
    pkgs-x86_64-linux = import nixpkgs {
      system = "x86_64-linux";
      config = {
        allowUnfree = true;
      };
      overlays = [
        nixgl.overlay
        unstable-x86_64-linux
        (import ./pkgs/netbird-ui-white-icons.nix)
      ];
    };
    unstable-aarch64-linux = final: _prev: {
      unstable = import nixpkgs-unstable {
        system = "aarch64-linux";
        config.allowUnfree = true;
      };
    };
    pkgs-aarch64-linux = import nixpkgs {
      system = "aarch64-linux";
      config.allowUnfree = true;
      overlays = [unstable-aarch64-linux];
    };

    # Cached aarch64 packages from standard nixpkgs for RPi overlay.
    # nixos-raspberrypi uses a custom nixpkgs fork that doesn't match cache.nixos.org.
    # We overlay Python and other packages from this cached instance.
    cachedPkgs-aarch64 = import nixpkgs {
      system = "aarch64-linux";
      config.allowUnfree = true;
    };

    # All hosts defined in hosts.nix
    hosts =
      (lib.evalModules {
        modules = [./hosts.nix ./services.nix];
        specialArgs = {inherit nixos-hardware;};
      }).config.hostConfig;

    # Full NixOS hosts only, used for the deploy-rs
    nixosHosts = lib.filterAttrs (hostName: hostConfig: hostConfig.kind == "nixos") hosts;

    # Common base modules for all configurations
    baseModules = [
      home-manager.nixosModules.home-manager
      disko.nixosModules.disko
      nix-flatpak.nixosModules.nix-flatpak
      ./modules/common.nix
      ./modules/ssh.nix
      ./modules/networking.nix
      ./users/admin.nix
    ];

    # Create a reusable function to generate modules list
    mkModulesList = {
      hostName,
      hostConfig,
      additionalModules ? [],
    }: let
      hostConfigFile = ./hosts/${hostName}.nix;
      hasHostConfig = builtins.pathExists hostConfigFile;
    in
      baseModules
      ++ (lib.optional hasHostConfig
        (builtins.trace "Loading ${hostName} config ${hostConfigFile}" hostConfigFile))
      # Ensure the hosts and services modules are always imported, inject host config
      ++ [./hosts.nix ./services.nix ({...}: {hostConfig.self = hostConfig;})]
      ++ hostConfig.extraModules or []
      ++ additionalModules;

    # Create nixosConfiguration for regular x86_64 hosts.
    mkSystem = {
      hostName,
      hostConfig,
      additionalModules ? [],
    }:
      lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules =
          mkModulesList {inherit hostName hostConfig additionalModules;}
          ++ [({...}: {nixpkgs.pkgs = pkgs-x86_64-linux;})];
      };

    # Function to create a deploy node entry
    mkNode = hostName: hostConfig: {
      hostname = "${hostName}.nb.krejci.io";
      sshUser = "admin";
      profiles.system = {
        user = "root";
        path =
          deploy-rs.lib.${
            if hostConfig.isRpi
            then "aarch64-linux"
            else "x86_64-linux"
          }.activate.nixos
          self.nixosConfigurations.${hostName};
      };
    };

    # Split hosts into regular and RPi
    rpiHosts = lib.filterAttrs (_: hostConfig: hostConfig.isRpi) nixosHosts;
    regularHosts = lib.filterAttrs (_: hostConfig: !hostConfig.isRpi) nixosHosts;
  in {
    formatter = {
      x86_64-linux = pkgs-x86_64-linux.alejandra;
      aarch64-linux = pkgs-aarch64-linux.alejandra;
    };

    # Generate nixosConfiguration for all hosts
    nixosConfigurations =
      # Regular x86_64 hosts use lib.nixosSystem.
      (builtins.mapAttrs
        (hostName: hostConfig: mkSystem {inherit hostName hostConfig;})
        regularHosts)
      # RPi hosts use nixos-raspberrypi.lib.nixosSystem with custom nixpkgs fork.
      # The fork has RPi boot loader patches and can't use standard nixpkgs.
      # We pass cachedPkgs-aarch64 to overlay Python and other slow-to-build packages.
      // (builtins.mapAttrs
        (hostName: hostConfig:
          nixos-raspberrypi.lib.nixosSystem {
            specialArgs = {inherit inputs nixos-raspberrypi cachedPkgs-aarch64;};
            modules = mkModulesList {inherit hostName hostConfig;};
          })
        rpiHosts);

    deploy.nodes = builtins.mapAttrs mkNode nixosHosts;

    # TODO enable deploy-rs checks
    # This is highly advised, and will prevent many possible mistakes
    # checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;

    image = {
      # Generate USB stick installer
      installer = let
        installerSystem = mkSystem {
          hostName = "iso";
          hostConfig = hosts.iso;
          additionalModules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ({...}: {
              isoImage.makeEfiBootable = true;
              isoImage.makeUsbBootable = true;
              isoImage.compressImage = false;
            })
          ];
        };
      in
        installerSystem.config.system.build.isoImage;

      # Generate SD card image for raspberry pi as final bootable system.
      # Uses nixosSystem with sd-image module directly, not nixosInstaller.
      # This produces a smaller image without installer profile bloat.
      # TODO: Consider adding a generic RPi installer image similar to ISO installer
      # that can be used to bootstrap any RPi host.
      sdcard =
        lib.genAttrs
        (builtins.attrNames rpiHosts)
        (hostName: let
          hostConfig = hosts.${hostName};
        in
          (nixos-raspberrypi.lib.nixosSystem {
            specialArgs = {inherit inputs nixos-raspberrypi cachedPkgs-aarch64;};
            modules =
              mkModulesList {inherit hostName hostConfig;}
              ++ [
                nixos-raspberrypi.nixosModules.sd-image
                ./modules/load-keys.nix
                ({lib, ...}: {
                  sdImage.compressImage = false;
                  # Reduce firmware partition from 1GB to 256MB for initial image.
                  # 1GB is for multi-generation boot, but fresh install only has one.
                  sdImage.firmwareSize = lib.mkForce 256;
                })
              ];
          }).config.system.build.sdImage);
    };

    # Declare hosts in outputs to be evaluable with nix eval,
    # this is usefull for wireguard-config generator
    hosts = hosts;

    # Import usefull scripts
    packages."x86_64-linux" = import ./scripts.nix {
      pkgs = pkgs-x86_64-linux;
      nixos-anywhere = nixos-anywhere.packages."x86_64-linux".nixos-anywhere;
    };

    # Tests for script functions
    checks."x86_64-linux" = let
      scripts = import ./scripts.nix {
        pkgs = pkgs-x86_64-linux;
        nixos-anywhere = nixos-anywhere.packages."x86_64-linux".nixos-anywhere;
      };
      # Test bcm2711 overlay workaround produces correct config.txt.
      # BCM2711 firmware skips overlays followed by empty dtoverlay= lines.
      rpi4-overlay-test = pkgs-x86_64-linux.runCommand "rpi4-overlay-test" {} ''
        config='${self.nixosConfigurations.prusa.config.hardware.raspberry-pi.config-generated}'

        # Overlays must be present
        echo "$config" | grep -q 'dtoverlay=disable-bt' || { echo "FAIL: disable-bt missing"; exit 1; }
        echo "$config" | grep -q 'dtoverlay=vc4-kms-v3d' || { echo "FAIL: vc4-kms-v3d missing"; exit 1; }

        # Must NOT have pattern: dtoverlay=<name> followed by dtoverlay= (empty).
        # This pattern causes bcm2711 firmware to skip the overlay.
        if echo "$config" | grep -Pzo 'dtoverlay=(disable-bt|vc4-kms-v3d)\n(dtparam=[^\n]*\n)*dtoverlay=\n' >/dev/null; then
          echo "FAIL: overlay followed by empty dtoverlay= line"
          echo "Config:"
          echo "$config"
          exit 1
        fi

        echo "OK: bcm2711 overlay workaround effective"
        touch $out
      '';
    in {
      inherit (scripts) script-lib-test validate-ssh-keys;
      inherit rpi4-overlay-test;
    };
  };
}

{
  description = "NixOS multi host configuration";

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

    # All hosts defined in hosts.nix
    hosts =
      (lib.evalModules {
        modules = [./hosts.nix];
        specialArgs = {inherit nixos-hardware;};
      }).config.hosts;

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
      # Ensure the hosts module is always imported, inject host config
      ++ [./hosts.nix ({...}: {hosts.self = hostConfig;})]
      ++ hostConfig.extraModules or []
      ++ additionalModules;

    # The main unit creating nixosConfiguration for a given host configuration
    mkSystem = {
      hostName,
      hostConfig,
      additionalModules ? [],
    }:
      lib.nixosSystem {
        system = hostConfig.system;
        specialArgs = {inherit inputs;};
        modules =
          mkModulesList
          {
            inherit hostName hostConfig additionalModules;
          }
          ++ [
            ({...}: {
              nixpkgs.pkgs =
                if hostConfig.system == "aarch64-linux"
                then pkgs-aarch64-linux
                else pkgs-x86_64-linux;
            })
          ];
      };

    # Function to create a deploy node entry
    mkNode = hostName: hostConfig: {
      hostname = "${hostName}.krejci.io";
      sshUser = "admin";
      profiles.system = {
        user = "root";
        path = deploy-rs.lib.${hostConfig.system}.activate.nixos self.nixosConfigurations.${hostName};
      };
    };
  in {
    formatter = {
      x86_64-linux = pkgs-x86_64-linux.alejandra;
      aarch64-linux = pkgs-aarch64-linux.alejandra;
    };

    # Generate nixosConfiguration for all hosts
    nixosConfigurations =
      builtins.mapAttrs
      (hostName: hostConfig:
        mkSystem {
          inherit hostName hostConfig;
        })
      nixosHosts;

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
            ./modules/load-keys.nix
            ({...}: {
              isoImage.makeEfiBootable = true;
              isoImage.makeUsbBootable = true;
              isoImage.compressImage = false;
            })
          ];
        };
      in
        installerSystem.config.system.build.isoImage;

      # Generate SD card image for raspberry pi
      sdcard =
        lib.genAttrs
        (builtins.attrNames (lib.filterAttrs
          (hostName: hostConfig: hostConfig.system == "aarch64-linux")
          hosts))
        (hostName:
          (self.nixosConfigurations.${hostName}.extendModules {
            modules = [
              "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
              ./modules/load-keys.nix
              ({...}: {
                sdImage.compressImage = false;
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
    in {
      inherit (scripts) script-lib-test validate-ssh-keys;
    };
  };
}

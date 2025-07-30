{
  description = "NixOS multi host configuration";

  inputs = {
    # Most of packages are fetched from the stable channel
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    # Some bleeding edge packages are fetch from unstable
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # A collection of NixOS modules covering hardware quirks
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # Manage a user environment
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
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
    # A calmer internet, without any gimmicks
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
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
    zen-browser,
    ...
  } @ inputs: let
    lib = nixpkgs.lib;

    zen-overlay = final: prev: {
      zen-browser = zen-browser.packages.x86_64-linux.default;
    };
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
        # Enable support for display link devices
        displaylink = {
          enable = true;
          # Use a fixed path relative to the repository
          driverFile = ./modules/displaylink/displaylink-600.zip;
          # Provide a fixed hash that you'll get after downloading the file
          # Add the hash here after downloading and running nix-prefetch-url file://$(pwd)/modules/displaylink/displaylink-600.zip
          sha256 = "1ixrklwk67w25cy77n7l0pq6j9i4bp4lkdr30kp1jsmyz8daaypw";
        };
      };
      overlays = [
        nixgl.overlay
        unstable-x86_64-linux
        zen-overlay
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
      ./modules/common.nix
      ./modules/ssh.nix
      ./modules/networking.nix
      ./modules/users/admin/user.nix
    ];

    # Create a reusable function to generate modules list
    mkModulesList = {
      hostName,
      hostConfig,
      additionalModules ? [],
    }: let
      hostConfigFile = ./hosts/${hostName}/configuration.nix;
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
      hostname = "${hostName}.vpn";
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

    # TODO find a way how to do checks together with the nokia / latitude hosts
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
  };
}

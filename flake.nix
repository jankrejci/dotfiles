{
  description = "NixOS multi host configuration";

  inputs = {
    # Most of packages are fetched from the stable channel
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    # Some bleeding edge packages are fetch from unstable
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Manage a user environment
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Atomic secret provisioning for NixOS based on sops 
    sops-nix.url = "github:Mic92/sops-nix";

    # nixgl is needed for alacritty outside of nixOS
    # refer to https://github.com/NixOS/nixpkgs/issues/122671
    # https://github.com/guibou/nixGL/#use-an-overlay
    nixgl.url = "github:guibou/nixGL";

    # Declarative partitioning and formatting
    disko.url = "github:nix-community/disko";
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, nixgl, sops-nix, disko, ... }:
    let
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
        config.allowUnfree = true;
        overlays = [ nixgl.overlay unstable-x86_64-linux ];
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
        overlays = [
          unstable-aarch64-linux
          # Some packages reports `ahci fail`, this bypasses that
          # https://discourse.nixos.org/t/does-pkgs-linuxpackages-rpi3-build-all-required-kernel-modules/42509
          (final: super: {
            makeModulesClosure = x:
              super.makeModulesClosure (x // { allowMissing = true; });
          })
        ];
      };

      # All hosts are defined within the host hostConfigs
      hostConfigs = import ./hosts.nix { inherit nixpkgs; };

      # Whether to load age key when building the image
      # `LOAD_KEYS=true nix build .#images.iso`
      loadKeys = builtins.getEnv "LOAD_KEYS" == "1";

      # Subset of host config used mainly for network configuration
      hostInfo = builtins.mapAttrs
        (hostName: config: {
          hostName = hostName;
          ipAddress = config.ipAddress;
          wgPublicKey = config.wgPublicKey;
        })
        hostConfigs;

      # The main unit creating nixosConfiguration for a given host configuration
      mkHost = { system ? "x86_64-linux", extraModules ? [ ], ... }@config: lib.nixosSystem {
        system = system;
        specialArgs = {
          pkgs =
            if system == "aarch64-linux"
            then pkgs-aarch64-linux
            else pkgs-x86_64-linux;
          hostConfig = config;
          hostInfo = hostInfo;
        };
        modules =
          let
            hostConfigFile = ./hosts/${config.hostName}/configuration.nix;
            hasHostConfig = builtins.pathExists hostConfigFile;
          in
          [
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            ./modules/common.nix
            ./modules/ssh.nix
            ./modules/wg-config.nix
          ]
          ++ (lib.optional hasHostConfig (builtins.trace "Loading host config" hostConfigFile))
          ++ (lib.optional loadKeys (builtins.trace "Loading age keys" ./modules/load-keys.nix))
          ++ extraModules;
      };
    in
    rec {
      # Generate nixosConfiguration for all hosts
      nixosConfigurations = builtins.mapAttrs
        (hostName: config: mkHost (config // { hostName = hostName; }))
        hostConfigs;

      # Image generator shortcuts
      # `LOAD_KEYS=1 nix build .#image.rpi4 --impure`
      image = {
        rpi4 = nixosConfigurations.rpi4.config.system.build.sdImage;
        prusa = nixosConfigurations.prusa.config.system.build.sdImage;
        iso = nixosConfigurations.iso.config.system.build.isoImage;
      };

      # Wireguard config generator shortcut for non-NixOS hosts
      # `nix build .#wg.nokia --impure`
      wg = {
        nokia = nixosConfigurations.nokia.config.system.build.wgConfig;
        latitude = nixosConfigurations.latitude.config.system.build.wgConfig;
      };

      # Generate homeConfiguration for non-NixOS host running home manager
      homeConfigurations = {
        latitude = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs-x86_64-linux;
          modules = [
            ./modules/users/jkr/home-ubuntu.nix
          ];
        };
      };
    };
}

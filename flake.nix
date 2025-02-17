{
  description = "NixOS configuration with system-wide packages and allowUnfree";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    sops-nix.url = "github:Mic92/sops-nix";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

      hostConfigs = import ./hosts.nix { inherit nixpkgs; };

      # Whether to load age key when building the image
      # `LOAD_KEYS=true nix build .#images.iso`
      loadKeys = builtins.getEnv "LOAD_KEYS" == "1";

      hostInfo = builtins.mapAttrs
        (hostName: config: {
          hostName = hostName;
          ipAddress = config.ipAddress;
          wgPublicKey = config.wgPublicKey;
        })
        hostConfigs;

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
      nixosConfigurations = builtins.mapAttrs
        (hostName: config: mkHost (config // { hostName = hostName; }))
        hostConfigs;

      image = {
        rpi4 = nixosConfigurations.rpi4.config.system.build.sdImage;
        prusa = nixosConfigurations.prusa.config.system.build.sdImage;
        iso = nixosConfigurations.iso.config.system.build.isoImage;
      };

      wg = {
        nokia = nixosConfigurations.nokia.config.system.build.wgConfig;
        latitude = nixosConfigurations.latitude.config.system.build.wgConfig;
      };

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

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
    # For accessing `deploy-rs`'s utility Nix functions
    deploy-rs.url = "github:serokell/deploy-rs";
    # Atomic secret provisioning for NixOS based on sops 
    sops-nix.url = "github:Mic92/sops-nix";
    # nixgl is needed for alacritty outside of nixOS
    # refer to https://github.com/NixOS/nixpkgs/issues/122671
    # https://github.com/guibou/nixGL/#use-an-overlay
    nixgl.url = "github:guibou/nixGL";
    # Declarative partitioning and formatting
    disko.url = "github:nix-community/disko";
  };

  outputs =
    { self
    , nixpkgs
    , nixpkgs-unstable
    , home-manager
    , deploy-rs
    , sops-nix
    , nixgl
    , disko
    , ...
    }:
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
        overlays = [ unstable-aarch64-linux ];
      };

      # Whether to load age key when building the image
      # `LOAD_KEYS=true nix build .#images.iso`
      loadKeys = builtins.getEnv "LOAD_KEYS" == "1";


      # All hosts defined in hosts.nix
      hosts = (lib.evalModules {
        modules = [ ./hosts.nix ];
        specialArgs = { inherit nixpkgs; };
      }).config.hosts;

      # Full NixOS hosts only, used for the deploy-rs
      nixosHosts = lib.filterAttrs (hostName: hostConfig: hostConfig.kind == "nixos") hosts;

      # The main unit creating nixosConfiguration for a given host configuration
      mkHost = hostName: hostConfig: lib.nixosSystem {
        system = hostConfig.system;
        specialArgs = {
          pkgs =
            if hostConfig.system == "aarch64-linux"
            then pkgs-aarch64-linux
            else pkgs-x86_64-linux;
        };
        modules =
          let
            hostConfigFile = ./hosts/${hostName}/configuration.nix;
            hasHostConfig = builtins.pathExists hostConfigFile;
          in
          [
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
            ./modules/common.nix
            ./modules/ssh.nix
            ./modules/networking.nix
            ./modules/wg-config.nix
            ./modules/users/admin/user.nix
          ]
          ++ (lib.optional hasHostConfig (builtins.trace "Loading host config" hostConfigFile))
          # Inject age key during the sdcard / iso build
          ++ (lib.optional loadKeys (builtins.trace "Loading age keys" ./modules/load-keys.nix))
          # Ensure the hosts module is always imported, inject host config
          ++ [ ./hosts.nix ({ config, ... }: { hosts.self = hostConfig; }) ]
          ++ hostConfig.extraModules;
      };

      # Function to create a deploy node entry
      mkNode = hostName: hostConfig: {
        hostname = "${hostName}.vpn";
        sshUser = "admin";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.${hostConfig.system}.activate.nixos self.nixosConfigurations.${hostName};
        };
        postBuildHook = ''
          nix sign-paths --key-file "$HOME/.config/nix/signing-key" $(nix path-info -r /nix/store)
        '';
      };
    in
    {
      # TODO create remote installation process
      # Generate nixosConfiguration for all hosts
      nixosConfigurations = builtins.mapAttrs mkHost hosts;

      deploy.nodes = builtins.mapAttrs mkNode nixosHosts;

      # TODO find a way how to do checks together with the nokia / latitude hosts
      # This is highly advised, and will prevent many possible mistakes
      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;

      # Image generator shortcuts
      # `LOAD_KEYS=1 nix build .#image.rpi4 --impure`
      image = {
        rpi4 = self.nixosConfigurations.rpi4.config.system.build.sdImage;
        prusa = self.nixosConfigurations.prusa.config.system.build.sdImage;
        iso = self.nixosConfigurations.iso.config.system.build.isoImage;
      };

      # TODO maybe use a standalone flake rather than ninixosConfigurations build
      # Wireguard config generator shortcut for non-NixOS hosts
      # `nix build .#wg.nokia --impure`
      wg = {
        nokia = self.nixosConfigurations.nokia.config.system.build.wgConfig;
        latitude = self.nixosConfigurations.latitude.config.system.build.wgConfig;
        optiplex = self.nixosConfigurations.optiplex.config.system.build.wgConfig;
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

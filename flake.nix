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
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, nixgl, sops-nix, ... }:
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
        overlays = [ unstable-aarch64-linux ];
      };

      hostConfigs = {
        vpsfree = {
          ipAddress = "192.168.99.1";
          wgPublicKey = "iWfrqdXV4bDQOCfhlZ2KRS7eq2B/QI440HylPrzJUww=";
          system = "x86_64-linux";
          extraModules = [
            ./modules/users/admin/user.nix
            ./modules/wg-server.nix
            ./modules/grafana.nix
            ./modules/vpsadminos.nix
          ];
        };
        rpi4 = {
          ipAddress = "192.168.99.2";
          wgPublicKey = "sUUZ9eIfyjqdEDij7vGnOe3sFbbF/eHQqS0RMyWZU0c=";
          system = "aarch64-linux";
          extraModules = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./modules/users/admin/user.nix
            ./modules/wg-client.nix
          ];
        };
        optiplex = {
          ipAddress = "192.168.99.3";
          wgPublicKey = "6QNJxFoSDKwqQjF6VgUEWP5yXXe4J3DORGo7ksQscFA=";
          system = "x86_64-linux";
          extraModules = [
            ./modules/users/jkr/user.nix
            ./modules/users/paja/user.nix
            ./modules/wg-client.nix
            ./modules/desktop.nix
          ];
        };
        thinkpad = {
          ipAddress = "192.168.99.4";
          wgPublicKey = "IzW6yPZJdrBC6PtfSaw7k4hjH+b/GjwvwiDLkLevLDI=";
          system = "x86_64-linux";
          extraModules = [
            ./modules/users/jkr/user.nix
            ./modules/users/paja/user.nix
            ./modules/wg-client.nix
            ./modules/desktop.nix
            ./modules/disable-nvidia.nix
          ];
        };
        latitude = {
          ipAddress = "192.168.99.5";
          wgPublicKey = "ggj+uqF/vij5V+fA5r9GIv5YuT9hX7OBp+lAGYh5SyQ=";
        };
        android = {
          ipAddress = "192.168.99.6";
          wgPublicKey = "HP+nPkrKwAxvmXjrI9yjsaGRMVXqt7zdcBGbD2ji83g=";
        };
      };

      hostInfo = builtins.mapAttrs
        (hostName: config: {
          hostName = hostName;
          ipAddress = config.ipAddress;
          wgPublicKey = config.wgPublicKey;
        })
        hostConfigs;

      mkHost = { system, extraModules ? [ ], ... }@config: lib.nixosSystem {
        system = system;
        specialArgs = {
          pkgs =
            if system == "aarch64-linux"
            then pkgs-aarch64-linux
            else pkgs-x86_64-linux;
          hostConfig = config;
          hostInfo = hostInfo;
        };
        modules = [
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          ./modules/common.nix
          ./modules/ssh.nix
          ./hosts/${config.hostName}/configuration.nix
        ] ++ extraModules;
      };
    in
    {
      nixosConfigurations = builtins.mapAttrs
        (hostName: config: mkHost (config // { hostName = hostName; }))
        hostConfigs;


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

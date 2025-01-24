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

      mkHost = { system, hostName, ipAddress, wgPublicKey, extraModules ? { } }: nixpkgs.lib.nixosSystem {
        system = system;
        specialArgs = {
          pkgs =
            if system == "aarch64-linux"
            then pkgs-aarch64-linux
            else pkgs-x86_64-linux;
          hostConfig = {
            hostName = hostName;
            ipAddress = ipAddress;
            wgPublicKey = wgPublicKey;
          };
        };
        modules = [
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          ./hosts/${hostName}/configuration.nix
        ] ++ extraModules;
      };
    in
    {
      nixosConfigurations = {
        optiplex = mkHost {
          system = "x86_64-linux";
          hostName = "optiplex";
          ipAddress = "192.168.99.3";
          wgPublicKey = "6QNJxFoSDKwqQjF6VgUEWP5yXXe4J3DORGo7ksQscFA=";
          extraModules = [
            ./modules/users/jkr/user.nix
            ./modules/users/paja/user.nix
          ];
        };

        thinkpad = mkHost {
          system = "x86_64-linux";
          hostName = "thinkpad";
          ipAddress = "192.168.99.4";
          wgPublicKey = "IzW6yPZJdrBC6PtfSaw7k4hjH+b/GjwvwiDLkLevLDI=";
          extraModules = [
            ./modules/users/jkr/user.nix
            ./modules/users/paja/user.nix
          ];
        };

        rpi4 = mkHost {
          system = "aarch64-linux";
          hostName = "rpi4";
          ipAddress = "192.168.99.2";
          wgPublicKey = "sUUZ9eIfyjqdEDij7vGnOe3sFbbF/eHQqS0RMyWZU0c=";
          extraModules = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./modules/users/admin/user.nix
          ];
        };

        vpsfree = mkHost {
          system = "x86_64-linux";
          hostName = "vpsfree";
          ipAddress = "192.168.99.1";
          wgPublicKey = "iWfrqdXV4bDQOCfhlZ2KRS7eq2B/QI440HylPrzJUww=";
          extraModules = [
            ./modules/users/admin/user.nix
          ];
        };
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

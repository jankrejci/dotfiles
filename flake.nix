{
  description = "NixOS configuration with system-wide packages and allowUnfree";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixgl is needed for alacritty outside of nixOS
    # refer to https://github.com/NixOS/nixpkgs/issues/122671
    # https://github.com/guibou/nixGL/#use-an-overlay
    nixgl.url = "github:guibou/nixGL";
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, nixgl, ... }:
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

    in
    {
      nixosConfigurations = {
        optiplex = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { pkgs = pkgs-x86_64-linux; };
          modules = [
            ./hosts/optiplex/configuration.nix
            ./modules/users/jkr/user.nix
            ./modules/users/paja/user.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users = {
                  jkr = { ... }: {
                    imports = [ ./modules/users/jkr/home.nix ];
                  };
                  paja = { ... }: {
                    imports = [ ./modules/users/paja/home.nix ];
                  };
                };
              };
            }
          ];
        };

        thinkpad = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { pkgs = pkgs-x86_64-linux; };
          modules = [
            ./hosts/thinkpad/configuration.nix
            ./modules/users/jkr/user.nix
            ./modules/users/paja/user.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users = {
                  jkr = { ... }: {
                    imports = [ ./modules/users/jkr/home.nix ];
                  };
                  paja = { ... }: {
                    imports = [ ./modules/users/paja/home.nix ];
                  };
                };
              };
            }
          ];
        };

        rpi4 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { pkgs = pkgs-aarch64-linux; };
          modules = [
            ./hosts/rpi4/configuration.nix
            ./modules/users/jkr/user.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users = {
                  jkr = { ... }: {
                    imports = [ ./modules/users/jkr/home-minimal.nix ];
                  };
                };
              };
            }
          ];
        };

        vpsfree = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { pkgs = pkgs-x86_64-linux; };
          modules = [
            ./hosts/vpsfree/configuration.nix
            ./modules/users/jkr/user.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users = {
                  jkr = { ... }: {
                    imports = [ ./modules/users/jkr/home-minimal.nix ];
                  };
                };
              };
            }
          ];
        };
      };

      homeConfigurations = {
        latitude = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs-x86_64-linux;
          modules = [
            {
              config.nixGLPrefix = "nixGL";
            }
            ./modules/users/jkr/home-ubuntu.nix
            ./modules/options.nix
          ];
        };
      };
    };
}

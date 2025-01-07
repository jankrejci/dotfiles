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

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixgl, ... }@inputs:
    {
      nixosConfigurations = {
        optiplex = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/optiplex/configuration.nix
            ./modules/users/users.nix
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
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/thinkpad/configuration.nix
            ./modules/users/users.nix
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
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/rpi4/configuration.nix
            ./modules/users/single-user.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users = {
                  jkr = { ... }: {
                    imports = [ ./modules/users/jkr/home-rpi.nix ];
                  };
                };
              };
            }
          ];
        };

        vpsfree = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            # Make overlay available system-wide
            ./hosts/vpsfree/configuration.nix
            ./modules/users/single-user.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users = {
                  jkr = { ... }: {
                    imports = [ ./modules/users/jkr/home-rpi.nix ];
                  };
                };
              };
            }
          ];
        };
      };
    };
}

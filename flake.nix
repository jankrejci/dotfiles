{
  description = "Home Manager configuration of jkr";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixgl is needed for alacritty outside of nixOS
    # refer to https://github.com/NixOS/nixpkgs/issues/122671
    # https://github.com/guibou/nixGL/#use-an-overlay
    nixgl.url = "github:guibou/nixGL";
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, nixgl, ... }:
    let
      system = "x86_64-linux";

      unstable-packages = final: _prev: {
        unstable = import nixpkgs-unstable {
          system = final.system;
          config.allowUnfree = true;
        };
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ nixgl.overlay unstable-packages ];
      };

      secrets = import ./secrets.nix;
    in
    {
      homeConfigurations.${secrets.username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [ ./home.nix ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };
    };
}

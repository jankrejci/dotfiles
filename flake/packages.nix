# perSystem outputs: formatter, packages, checks
{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    self',
    ...
  }: let
    # Overlay for unstable packages
    unstableOverlay = final: _prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    };

    # Configure pkgs with overlays
    pkgsWithOverlays = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        unstableOverlay
        (import ../pkgs/netbird-ui-white-icons.nix)
      ];
    };

    scripts = import ../scripts.nix {
      pkgs = pkgsWithOverlays;
      nixos-anywhere = inputs.nixos-anywhere.packages.${system}.nixos-anywhere;
    };
  in {
    # Use pkgs with overlays for this system
    _module.args.pkgs = pkgsWithOverlays;

    formatter = pkgsWithOverlays.alejandra;

    packages =
      if system == "x86_64-linux"
      then scripts
      else {};

    checks =
      if system == "x86_64-linux"
      then {
        inherit (scripts) script-lib-test validate-ssh-keys;
      }
      else {};
  };
}

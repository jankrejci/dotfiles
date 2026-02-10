# Per-system flake outputs
#
# - formatter: alejandra for nix files
# - packages: deployment scripts
# - checks: validation tests
# - overlays: unstable and master nixpkgs
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

    # Overlay for master branch packages
    masterOverlay = final: _prev: {
      master = import inputs.nixpkgs-master {
        inherit system;
        config.allowUnfree = true;
      };
    };

    # Pinned nixpkgs for immich to control update timing
    immichOverlay = final: _prev: {
      immich-pinned = import inputs.nixpkgs-immich {
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
        masterOverlay
        immichOverlay
        (import ../pkgs/netbird-ui-white-icons.nix)
        inputs.agenix-rekey.overlays.default
      ];
    };

    scripts = import ../scripts {
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

    # agenix-rekey configuration
    agenix-rekey.nixosConfigurations = inputs.self.nixosConfigurations;
  };
}

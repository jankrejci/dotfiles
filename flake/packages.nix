# Per-system flake outputs
#
# - formatter: alejandra for nix files
# - packages: deployment scripts
# - checks: validation tests
# - overlays: unstable and master nixpkgs
{inputs, ...}: let
  # Nixpkgs overlays using final.system so they work for any architecture
  unstableOverlay = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };

  masterOverlay = final: _prev: {
    master = import inputs.nixpkgs-master {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };

  immichOverlay = final: _prev: {
    immich-pinned = import inputs.nixpkgs-immich {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };
in {
  flake.overlays = {
    inherit unstableOverlay masterOverlay immichOverlay;
  };

  perSystem = {
    pkgs,
    system,
    self',
    ...
  }: let
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

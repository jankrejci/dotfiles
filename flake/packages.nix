# Per-system flake outputs
#
# - formatter: alejandra for nix files
# - packages: deployment scripts
# - checks: validation tests
# - overlays: unstable, pinned immich nixpkgs and local packages
{inputs, ...}: let
  # Nixpkgs overlays using final.system so they work for any architecture
  unstableOverlay = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };

  prusaObicoOverlay = final: _prev: {
    prusa-obico = final.callPackage ../pkgs/prusa-obico.nix {};
  };

  immichOverlay = final: _prev: {
    immich-pinned = import inputs.nixpkgs-immich {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };
in {
  flake.overlays = {
    inherit unstableOverlay immichOverlay prusaObicoOverlay;
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
        immichOverlay
        prusaObicoOverlay
        # Tray icon color is baked in at build time, so it cannot follow the
        # runtime light/dark theme toggle. darkPalette's base04 dark-foreground
        # shade is used because it stays readable against both panel variants.
        (import ../pkgs/netbird-ui-icons.nix {
          color = (import ../modules/palettes.nix).darkPalette.base04;
        })
        (import ../pkgs/rofi-scroll-anchor.nix)
        (import ../pkgs/fwupd-efi-signed.nix)
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
      then scripts // {inherit (pkgsWithOverlays) prusa-obico;}
      else {};

    checks =
      if system == "x86_64-linux"
      then {
        inherit (scripts) script-lib-test validate-ssh-keys;
        # Running the package build also runs its cargo tests.
        inherit (self'.packages) prusa-obico;
        # The crate denies unwrap, indexing and panics through clippy lints, which only clippy enforces.
        # Reusing the package derivation gives the check the vendored dependencies offline.
        prusa-obico-clippy = self'.packages.prusa-obico.overrideAttrs (old: {
          pname = "prusa-obico-clippy";
          nativeBuildInputs = old.nativeBuildInputs ++ [pkgsWithOverlays.clippy];
          doCheck = false;
          postInstall = "";
          buildPhase = ''
            runHook preBuild
            cargo clippy --all-targets --offline -- -D warnings
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            touch $out
            runHook postInstall
          '';
        });
      }
      else {};

    # agenix-rekey configuration
    agenix-rekey.nixosConfigurations =
      inputs.self.nixosConfigurations // {iso = inputs.self.installerSystem;};
  };
}

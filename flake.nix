{
  description = "NixOS multi host configuration";

  # Binary cache for nixos-raspberrypi packages like ffmpeg-headless and kernel.
  nixConfig = {
    extra-substituters = ["https://nixos-raspberrypi.cachix.org"];
    extra-trusted-public-keys = ["nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="];
  };

  inputs = {
    # Flake-parts for modular flake organization
    flake-parts.url = "github:hercules-ci/flake-parts";
    # Most packages are fetched from the stable channel
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    # Some bleeding edge packages are fetched from unstable
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # Master branch for packages not yet in unstable
    nixpkgs-master.url = "github:nixos/nixpkgs/master";
    # A collection of NixOS modules covering hardware quirks
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # Manage a user environment
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # For accessing deploy-rs utility Nix functions
    deploy-rs.url = "github:serokell/deploy-rs";
    # Declarative partitioning and formatting
    disko.url = "github:nix-community/disko";
    # Install NixOS everywhere via SSH
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    # SOPS for managing secrets via age encryption
    sops-nix.url = "github:mic92/sops-nix";
    # Raspberry Pi NixOS support with RPi kernel and proper config.txt generation
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];
      imports = [./flake];

      # Add the rpi4-overlay-test check that needs access to self
      perSystem = {
        pkgs,
        system,
        self',
        ...
      }:
        if system == "x86_64-linux"
        then {
          checks.rpi4-overlay-test = pkgs.runCommand "rpi4-overlay-test" {} ''
            config='${inputs.self.nixosConfigurations.prusa.config.hardware.raspberry-pi.config-generated}'

            # Overlays must be present
            echo "$config" | grep -q 'dtoverlay=disable-bt' || { echo "FAIL: disable-bt missing"; exit 1; }
            echo "$config" | grep -q 'dtoverlay=vc4-kms-v3d' || { echo "FAIL: vc4-kms-v3d missing"; exit 1; }

            # Must NOT have pattern: dtoverlay=<name> followed by dtoverlay= (empty)
            if echo "$config" | grep -Pzo 'dtoverlay=(disable-bt|vc4-kms-v3d)\n(dtparam=[^\n]*\n)*dtoverlay=\n' >/dev/null; then
              echo "FAIL: overlay followed by empty dtoverlay= line"
              echo "Config:"
              echo "$config"
              exit 1
            fi

            echo "OK: bcm2711 overlay workaround effective"
            touch $out
          '';
        }
        else {};
    };
}

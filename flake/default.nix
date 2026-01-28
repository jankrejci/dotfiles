# Flake-parts module imports for modular flake organization
#
# Each submodule handles a specific concern:
# - options.nix: flake and NixOS-level homelab options
# - packages.nix: per-system formatter, packages, checks
# - hosts.nix: NixOS configurations and host definitions
# - deploy.nix: deploy-rs node configuration
# - images.nix: ISO and SD card image builders
{inputs, ...}: {
  imports = [
    ./options.nix
    ./packages.nix
    ./hosts.nix
    ./deploy.nix
    ./images.nix
    inputs.agenix-rekey.flakeModule
  ];
}

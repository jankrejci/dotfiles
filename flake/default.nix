# Flake-parts module that wraps existing flake outputs.
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

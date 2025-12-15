# Flake-parts module that wraps existing flake outputs.
{
  imports = [
    ./options.nix
    ./packages.nix
    ./hosts.nix
    ./deploy.nix
    ./images.nix
  ];
}

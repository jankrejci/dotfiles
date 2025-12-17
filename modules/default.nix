# Base modules imported for all hosts
{...}: {
  imports = [
    ./options.nix
    ./monitoring.nix
    ./common.nix
    ./ssh.nix
    ./networking.nix
  ];
}

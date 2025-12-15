# Single import point for all homelab modules
# This simplifies the module import in nixosConfigurations
{...}: {
  imports = [
    # Homelab options and monitoring
    ./options.nix
    ./monitoring.nix

    # Base modules always needed
    ./common.nix
    ./ssh.nix
    ./networking.nix

    # Service modules with homelab.X.enable pattern
    ./grafana.nix
    ./prometheus.nix
    ./immich.nix
    ./ntfy.nix
    ./octoprint.nix
  ];
}

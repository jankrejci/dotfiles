# Service modules with homelab.X.enable pattern
# All modules are imported but disabled by default.
# Enable via host.homelab.X.enable in flake/hosts.nix
{...}: {
  imports = [
    # Shared infrastructure
    ./nginx.nix
    ./postgresql.nix
    ./redis.nix

    # Services
    ./acme.nix
    ./grafana.nix
    ./immich.nix
    ./immich-public-proxy.nix
    ./jellyfin.nix
    ./loki.nix
    ./lorawan-gateway.nix
    ./ntfy.nix
    ./octoprint.nix
    ./prometheus.nix
    ./webcam.nix
    ./wireguard.nix
  ];
}

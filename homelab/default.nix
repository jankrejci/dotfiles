# Service modules with homelab.X.enable pattern
# All modules are imported but disabled by default.
# Enable via host.homelab.X.enable in flake/hosts.nix
{...}: {
  imports = [
    # Shared infrastructure
    ./backup.nix
    ./nginx.nix
    ./postgresql.nix
    ./redis.nix

    # Services
    ./acme.nix
    ./dex.nix
    ./netbird-gateway.nix
    ./netbird-server.nix
    ./grafana.nix
    ./immich.nix
    ./immich-public-proxy.nix
    ./jellyfin.nix
    ./loki.nix
    ./lorawan-gateway.nix
    ./memos.nix
    ./ntfy.nix
    ./octoprint.nix
    ./printer.nix
    ./prometheus.nix
    ./tunnel.nix
    ./watchdog.nix
    ./webcam.nix

    # Health check aggregator
    ./health-check.nix
  ];
}

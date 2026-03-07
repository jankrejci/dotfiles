# Service modules with homelab.X.enable pattern
# All modules are imported but disabled by default.
# Enable via host.homelab.X.enable in flake/hosts.nix
#
# Extraction goal: these modules and core modules/ will become a standalone
# reusable NixOS module flake. Consumers import and enable services via
# homelab.X.enable. Two roles: homelab-server and public-proxy.
#
# Remaining blockers for extraction:
# - Secrets: modules use relative rekeyFile paths that won't exist in a library
#   flake. Each module needs secret path options so consumers point to their own.
# - Assets: icons, grafana dashboards, ntfy templates ship in ../assets/ and
#   need bundling in the library flake with consumer override support.
{...}: {
  imports = [
    # Shared infrastructure
    ./backup.nix
    ./nginx.nix
    ./postgresql.nix
    ./redis.nix

    # Services
    ./acme.nix
    ./dashboard.nix
    ./dex.nix
    ./netbird-signal.nix
    ./netbird-server.nix
    ./grafana.nix
    ./immich.nix
    ./immich-public-proxy.nix
    ./jellyfin.nix
    ./loki.nix
    ./lorawan-gateway.nix
    ./memos.nix
    ./network-monitor.nix
    ./ntfy.nix
    ./octoprint.nix
    ./printer.nix
    ./prometheus.nix
    ./tunnel.nix
    ./vaultwarden.nix
    ./watchdog.nix
    ./webcam.nix

    # Health check aggregator
    ./health-check.nix
  ];
}

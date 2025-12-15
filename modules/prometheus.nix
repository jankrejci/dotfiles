# Prometheus monitoring with homelab enable flag
{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.prometheus;
  services = config.serviceConfig;
  domain = "${services.global.domain}";
  peerDomain = "nb.${domain}";
in {
  options.homelab.prometheus = {
    # Default true preserves existing behavior during transition
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Prometheus metrics collection";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      # Keep metrics for 6 months
      retentionTime = "180d";
      # 127.0.0.1 only - accessed via nginx proxy (defense in depth)
      listenAddress = "127.0.0.1";
      # Serve from subpath /prometheus/ (shares domain with Grafana)
      extraFlags = [
        "--web.external-url=https://${services.grafana.subdomain}.${domain}/prometheus"
        "--web.route-prefix=/prometheus"
      ];
      globalConfig.scrape_interval = "10s";
      scrapeConfigs = [
        {
          job_name = "prometheus";
          static_configs = [{targets = ["127.0.0.1:${toString services.prometheus.port}"];}];
          metrics_path = "/prometheus/metrics";
        }
        {
          # Node exporter from all NixOS hosts in the fleet
          job_name = "node";
          metrics_path = "/metrics/node";
          static_configs = [
            {
              targets = let
                makeTarget = hostName: _: "${hostName}.${peerDomain}:${toString services.metrics.port}";
                # Filter out "self" reference injected by flake.nix
                nixosHosts = lib.filterAttrs (name: hostConfig: name != "self" && hostConfig.kind == "nixos") config.hostConfig;
              in
                lib.mapAttrsToList makeTarget nixosHosts;
            }
          ];
        }
        {
          job_name = "immich";
          metrics_path = "/metrics/immich";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${toString services.metrics.port}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "immich-microservices";
          metrics_path = "/metrics/immich-microservices";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${toString services.metrics.port}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "ntfy";
          metrics_path = "/metrics/ntfy";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${toString services.metrics.port}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "postgres";
          metrics_path = "/metrics/postgres";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${toString services.metrics.port}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "redis";
          metrics_path = "/metrics/redis";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${toString services.metrics.port}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "nginx";
          metrics_path = "/metrics/nginx";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${toString services.metrics.port}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "wireguard";
          metrics_path = "/metrics/wireguard";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${toString services.metrics.port}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "octoprint";
          metrics_path = "/metrics/octoprint";
          static_configs = [
            {
              targets = ["prusa.${peerDomain}:${toString services.metrics.port}"];
              labels = {host = "prusa";};
            }
          ];
        }
      ];
    };
  };
}

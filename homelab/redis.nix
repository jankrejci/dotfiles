# Shared Redis cache server
#
# - in-memory key-value store
# - used by immich and other services
# - listens on localhost only
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.redis;
in {
  options.homelab.redis = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Redis cache";
    };
  };

  config = lib.mkIf cfg.enable {
    services.redis.servers."" = {
      enable = true;
      bind = "127.0.0.1";
      port = 6379;
    };

    # Redis prometheus exporter
    services.prometheus.exporters.redis = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9121;
    };

    # Metrics endpoint
    services.nginx.virtualHosts."metrics".locations."/metrics/redis".proxyPass = "http://127.0.0.1:9121/metrics";

    # Scrape target
    homelab.scrapeTargets = [
      {
        job = "redis";
        metricsPath = "/metrics/redis";
      }
    ];

    # Alert
    homelab.alerts.redis = [
      {
        alert = "RedisDown";
        expr = ''redis_up{job="redis",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Redis is down";
      }
    ];

    # Health check
    homelab.healthChecks = [
      {
        name = "Redis";
        script = pkgs.writeShellApplication {
          name = "health-check-redis";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet redis.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

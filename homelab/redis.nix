# Shared Redis configuration for homelab services
{
  config,
  lib,
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
  };
}

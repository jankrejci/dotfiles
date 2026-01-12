# Shared PostgreSQL configuration for homelab services
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.postgresql;
in {
  options.homelab.postgresql = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable PostgreSQL database";
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql.enable = true;

    # PostgreSQL prometheus exporter
    services.prometheus.exporters.postgres = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9187;
      runAsLocalSuperUser = true;
    };

    # Metrics endpoint
    services.nginx.virtualHosts."metrics".locations."/metrics/postgres".proxyPass = "http://127.0.0.1:9187/metrics";

    # Scrape target
    homelab.scrapeTargets = [
      {
        job = "postgres";
        metricsPath = "/metrics/postgres";
      }
    ];

    # Alert
    homelab.alerts.postgres = [
      {
        alert = "PostgresDown";
        expr = ''pg_up{job="postgres",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "PostgreSQL is down";
      }
    ];

    # Health check
    homelab.healthChecks = [
      {
        name = "PostgreSQL";
        script = pkgs.writeShellApplication {
          name = "health-check-postgresql";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet postgresql.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

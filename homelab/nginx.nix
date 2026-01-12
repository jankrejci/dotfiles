# Shared nginx configuration for homelab services
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.nginx;
in {
  options.homelab.nginx = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable nginx reverse proxy";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.enable = true;

    # Wait for "services" dummy interface before nginx binds to service IPs
    systemd.services.nginx.after = ["sys-subsystem-net-devices-services.device"];

    # Enable stub_status for metrics
    services.nginx.statusPage = true;

    # Nginx prometheus exporter
    services.prometheus.exporters.nginx = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9113;
      scrapeUri = "http://127.0.0.1/nginx_status";
    };

    # Metrics endpoint
    services.nginx.virtualHosts."metrics".locations."/metrics/nginx".proxyPass = "http://127.0.0.1:9113/metrics";

    # Scrape target
    homelab.scrapeTargets = [
      {
        job = "nginx";
        metricsPath = "/metrics/nginx";
      }
    ];

    # Alert
    homelab.alerts.nginx = [
      {
        alert = "NginxFailed";
        expr = ''node_systemd_unit_state{name="nginx.service",state="failed",host="${config.homelab.host.hostName}"} > 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Nginx service failed";
      }
    ];

    # Health check
    homelab.healthChecks = [
      {
        name = "Nginx";
        script = pkgs.writeShellApplication {
          name = "health-check-nginx";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet nginx.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

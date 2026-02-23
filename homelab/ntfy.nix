# Ntfy push notification service
#
# - receives alerts from prometheus alertmanager
# - mobile app notifications via UnifiedPush
# - nginx reverse proxy with TLS
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.ntfy;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  ntfyDomain = "${cfg.subdomain}.${domain}";
in {
  options.homelab.ntfy = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Ntfy notification service";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = {
      ntfy = lib.mkOption {
        type = lib.types.port;
        description = "Port for ntfy server";
      };

      metrics = lib.mkOption {
        type = lib.types.port;
        description = "Port for Prometheus metrics endpoint";
      };
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "ntfy";
      description = "Subdomain for ntfy";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [ntfyDomain];

    # Allow HTTPS on VPN interface only
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

    # Use unstable ntfy-sh for template support (requires >= 2.14.0)
    services.ntfy-sh = {
      enable = true;
      package = pkgs.unstable.ntfy-sh;
      settings = {
        # Listen on 127.0.0.1 only, accessed via nginx proxy (defense in depth)
        listen-http = "127.0.0.1:${toString cfg.port.ntfy}";
        base-url = "https://${ntfyDomain}";
        # Authentication: read-only by default, publishing requires tokens
        auth-default-access = "read-only";
        # Grafana user can publish via token, everyone else can read
        auth-file = "/var/lib/ntfy-sh/user.db";
        # Template directory for custom webhook formatting
        template-dir = "/var/lib/ntfy-sh/templates";
        # Expose Prometheus metrics on 127.0.0.1 only
        metrics-listen-http = "127.0.0.1:${toString cfg.port.metrics}";
      };
    };

    # Install webhook templates for Prometheus alerts
    systemd.tmpfiles.rules = [
      "d /var/lib/ntfy-sh/templates 0755 ntfy-sh ntfy-sh -"
      "L+ /var/lib/ntfy-sh/templates/prometheus-host.yml - - - - ${../assets/ntfy/prometheus-host.yml}"
      "L+ /var/lib/ntfy-sh/templates/prometheus-service.yml - - - - ${../assets/ntfy/prometheus-service.yml}"
      "L+ /var/lib/ntfy-sh/templates/default.yml - - - - ${../assets/ntfy/default.yml}"
    ];

    services.nginx.virtualHosts.${ntfyDomain} = {
      listenAddresses = [cfg.ip];
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port.ntfy}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    # Ntfy metrics via unified metrics proxy
    services.nginx.virtualHosts."metrics".locations."/metrics/ntfy".proxyPass = "http://127.0.0.1:${toString cfg.port.metrics}/metrics";

    homelab.scrapeTargets = [
      {
        job = "ntfy";
        metricsPath = "/metrics/ntfy";
        watchdog = true;
      }
    ];

    # Bootstrap limitation: NtfyDown alert routes through ntfy itself, so it
    # cannot fire when ntfy is actually down. The watchdog email path on vpsfree
    # covers this case independently.
    homelab.alerts.ntfy = [
      {
        alert = "NtfyDown";
        expr = ''up{job="ntfy"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Ntfy notification service is down";
      }
    ];

    homelab.dashboardEntries = [
      {
        name = "Ntfy";
        url = "https://${ntfyDomain}";
        icon = ../assets/dashboard-icons/ntfy.svg;
      }
    ];

    # Health check
    homelab.healthChecks = [
      {
        name = "Ntfy";
        script = pkgs.writeShellApplication {
          name = "health-check-ntfy";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet ntfy-sh.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

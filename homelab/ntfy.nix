# Ntfy notification service with homelab enable flag
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

    port = lib.mkOption {
      type = lib.types.port;
      default = 2586;
      description = "Port for ntfy server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "ntfy";
      description = "Subdomain for ntfy";
    };
  };

  config = lib.mkIf cfg.enable {
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
        listen-http = "127.0.0.1:${toString cfg.port}";
        base-url = "https://${ntfyDomain}";
        # Authentication: read-only by default, publishing requires tokens
        auth-default-access = "read-only";
        # Grafana user can publish via token, everyone else can read
        auth-file = "/var/lib/ntfy-sh/user.db";
        # Template directory for custom webhook formatting
        template-dir = "/var/lib/ntfy-sh/templates";
        # Expose Prometheus metrics on 127.0.0.1 only
        metrics-listen-http = "127.0.0.1:9091";
      };
    };

    # Install webhook templates for Prometheus alerts
    systemd.tmpfiles.rules = [
      "d /var/lib/ntfy-sh/templates 0755 ntfy-sh ntfy-sh -"
      "L+ /var/lib/ntfy-sh/templates/prometheus-host.yml - - - - ${../assets/ntfy/prometheus-host.yml}"
      "L+ /var/lib/ntfy-sh/templates/prometheus-service.yml - - - - ${../assets/ntfy/prometheus-service.yml}"
      "L+ /var/lib/ntfy-sh/templates/default.yml - - - - ${../assets/ntfy/default.yml}"
    ];

    # Wait for services interface before binding
    systemd.services.nginx.after = ["sys-subsystem-net-devices-services.device"];

    services.nginx = {
      enable = true;
      virtualHosts.${ntfyDomain} = {
        listenAddresses = [cfg.ip];
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
      # Ntfy metrics via unified metrics proxy
      virtualHosts."metrics".locations."/metrics/ntfy".proxyPass = "http://127.0.0.1:9091/metrics";
    };
  };
}

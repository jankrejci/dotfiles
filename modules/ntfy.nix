# Ntfy notification service with homelab enable flag
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.ntfy;
  # Prefer homelab namespace, fall back to old options during transition
  services = config.homelab.services or config.serviceConfig;
  host = config.homelab.host or config.hostConfig.self;
  # Use fallback values until homelab namespace is populated by flake
  domain = services.global.domain or "krejci.io";
  ntfyDomain = "${services.ntfy.subdomain or "ntfy"}.${domain}";
in {
  options.homelab.ntfy = {
    # Default true preserves existing behavior during transition
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Ntfy notification service";
    };
  };

  config = lib.mkIf cfg.enable {
    # Allow HTTPS on VPN interface only
    networking.firewall.interfaces."${services.netbird.interface or "nb-homelab"}".allowedTCPPorts = [
      (services.https.port or 443)
    ];

    # Use unstable ntfy-sh for template support (requires >= 2.14.0)
    services.ntfy-sh = {
      enable = true;
      package = pkgs.unstable.ntfy-sh;
      settings = {
        # Listen on 127.0.0.1 only, accessed via nginx proxy (defense in depth)
        listen-http = "127.0.0.1:${toString (services.ntfy.port or 2586)}";
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

    # Install custom Grafana template
    systemd.tmpfiles.rules = [
      "d /var/lib/ntfy-sh/templates 0755 ntfy-sh ntfy-sh -"
      "L+ /var/lib/ntfy-sh/templates/grafana.yml - - - - ${./ntfy/grafana.yml}"
    ];

    # Wait for services interface before binding
    systemd.services.nginx.after = ["sys-subsystem-net-devices-services.device"];

    services.nginx = {
      enable = true;
      virtualHosts.${ntfyDomain} = {
        listenAddresses = [host.services.ntfy.ip or "127.0.0.1"];
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString (services.ntfy.port or 2586)}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
      # Ntfy metrics via unified metrics proxy
      virtualHosts."metrics".locations."/metrics/ntfy".proxyPass = "http://127.0.0.1:9091/metrics";
    };
  };
}

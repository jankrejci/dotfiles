# Immich public sharing proxy
#
# Exposes shared albums without exposing Immich directly.
# Runs on thinkcenter alongside Immich, proxied to the internet via vpsfree.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.immich-public-proxy;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  shareDomain = "${cfg.subdomain}.${domain}";
in {
  options.homelab.immich-public-proxy = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Immich public sharing proxy";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      description = "Port for immich-public-proxy server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "share";
      description = "Subdomain for public sharing";
    };

    tunnel = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Expose via public tunnel through VPS";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals cfg.tunnel [
      {
        assertion = config.homelab.tunnel.enable;
        message = "immich-public-proxy tunnel requires homelab.tunnel";
      }
    ];

    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [shareDomain];

    # Immich Public Proxy - allows public sharing without exposing Immich
    services.immich-public-proxy = {
      enable = true;
      # Connect to Immich on localhost, no TLS overhead
      immichUrl = "http://127.0.0.1:${toString config.homelab.immich.port}";
      port = cfg.port;
      settings = {
        # Show home page with shield icon
        showHomePage = true;
        # Allow original quality downloads
        downloadOriginalPhoto = true;
        # Disable ZIP downloads of entire shares
        allowDownloadAll = 0;
      };
    };

    # Allow HTTPS on VPN interface
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

    # Allow HTTPS on tunnel interface for proxy traffic from VPS
    networking.firewall.interfaces."wg0".allowedTCPPorts = lib.mkIf cfg.tunnel [
      services.https.port
    ];

    # Nginx reverse proxy, accessible via VPN and optionally via tunnel
    services.nginx.virtualHosts.${shareDomain} = {
      listenAddresses = [cfg.ip] ++ lib.optional cfg.tunnel config.homelab.tunnel.ip;
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    homelab.alerts.immich-public-proxy = [
      {
        alert = "ImmichPublicProxyDown";
        expr = ''node_systemd_unit_state{name="immich-public-proxy.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Immich public proxy is down";
      }
    ];

    homelab.healthChecks = [
      {
        name = "Immich Public Proxy";
        script = pkgs.writeShellApplication {
          name = "health-check-immich-public-proxy";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet immich-public-proxy.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

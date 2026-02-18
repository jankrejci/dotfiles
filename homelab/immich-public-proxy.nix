# Immich public sharing proxy
#
# Exposes shared albums without exposing Immich directly.
# Runs on thinkcenter alongside Immich, proxied to the internet via vpsfree.
{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.immich-public-proxy;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  shareDomain = "${cfg.subdomain}.${domain}";

  # WG tunnel IP so vpsfree can proxy share traffic
  wgIp = config.homelab.wireguard.ip;
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
      default = 2284;
      description = "Port for immich-public-proxy server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "share";
      description = "Subdomain for public sharing";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.wireguard.enable;
        message = "immich-public-proxy requires homelab.wireguard for vpsfree proxy";
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

    # Nginx reverse proxy, accessible via VPN and WG tunnel from vpsfree
    services.nginx.virtualHosts.${shareDomain} = {
      listenAddresses = [cfg.ip wgIp];
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}

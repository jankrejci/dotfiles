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
  httpsPort = services.https.port;
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
      default = 2283;
      description = "Port for immich-public-proxy server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "share";
      description = "Subdomain for public sharing";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      description = "Network interface for public firewall rules";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [shareDomain];

    # Immich Public Proxy - allows public sharing without exposing Immich
    services.immich-public-proxy = {
      enable = true;
      # Connect to Immich via Netbird VPN
      immichUrl = "https://${config.homelab.immich.subdomain}.${domain}";
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

    # Open HTTPS on public interface
    networking.firewall.interfaces."${cfg.interface}".allowedTCPPorts = [httpsPort];

    # Nginx reverse proxy - publicly accessible
    services.nginx = {
      enable = true;
      virtualHosts.${shareDomain} = {
        # Listen on all interfaces (public service, needs to be accessible from both
        # public internet and VPN clients via Netbird DNS extra label)
        listenAddresses = ["0.0.0.0"];
        # Enable HTTPS with Let's Encrypt wildcard certificate
        forceSSL = true;
        useACMEHost = "${domain}";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };
  };
}

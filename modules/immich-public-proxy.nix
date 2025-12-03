{config, ...}: let
  proxy = config.serviceConfig.immich-public-proxy;
  domain = "krejci.io";
  shareDomain = "${proxy.subdomain}.${domain}";
  httpsPort = 443;
in {
  # Immich Public Proxy - allows public sharing without exposing Immich
  services.immich-public-proxy = {
    enable = true;
    # Connect to Immich via Netbird VPN
    immichUrl = "https://${config.serviceConfig.immich.subdomain}.${domain}";
    port = proxy.port;
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
  networking.firewall.interfaces."${proxy.interface}".allowedTCPPorts = [httpsPort];

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
        proxyPass = "http://127.0.0.1:${toString proxy.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}

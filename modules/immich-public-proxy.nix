{config, ...}: let
  services = config.serviceConfig;
  domain = services.global.domain;
  shareDomain = "${services.immich-public-proxy.subdomain}.${domain}";
  httpsPort = services.https.port;
in {
  # Immich Public Proxy - allows public sharing without exposing Immich
  services.immich-public-proxy = {
    enable = true;
    # Connect to Immich via Netbird VPN
    immichUrl = "https://${services.immich.subdomain}.${domain}";
    port = services.immich-public-proxy.port;
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
  networking.firewall.interfaces."${services.immich-public-proxy.interface}".allowedTCPPorts = [httpsPort];

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
        proxyPass = "http://127.0.0.1:${toString services.immich-public-proxy.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}

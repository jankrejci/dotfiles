{...}: let
  domain = "krejci.io";
  shareDomain = "share.${domain}";
  proxyPort = 2283;
  publicIp = "37.205.13.227";
  publicInterface = "venet0";
in {
  # Immich Public Proxy - allows public sharing without exposing Immich
  services.immich-public-proxy = {
    enable = true;
    # Connect to Immich via Netbird VPN
    immichUrl = "https://immich.${domain}";
    port = proxyPort;
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
  networking.firewall.interfaces.${publicInterface}.allowedTCPPorts = [443];

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
        proxyPass = "http://localhost:${toString proxyPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}

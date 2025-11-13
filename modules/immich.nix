{config, ...}: let
  domain = "x.nb";
  immichDomain = "immich.${domain}";
  immichPort = 2283;
in {
  # Allow nginx on VPN interface (proxies to Immich)
  networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [80 443];

  services.immich = {
    enable = true;
    # Listen on all interfaces, security enforced via firewall
    host = "0.0.0.0";
    port = immichPort;
    # Store media in /var/lib/immich
    mediaLocation = "/var/lib/immich";
  };

  # Nginx reverse proxy - accessible via immich.x.nb
  services.nginx = {
    enable = true;
    virtualHosts.${immichDomain} = {
      listenAddresses = ["0.0.0.0"];
      locations."/" = {
        proxyPass = "http://localhost:${toString immichPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}

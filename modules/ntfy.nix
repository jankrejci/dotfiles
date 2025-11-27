{
  config,
  pkgs,
  ...
}: let
  domain = "krejci.io";
  ntfyDomain = "ntfy." + domain;
  ntfyPort = 2586;
  vpnInterface = "nb-homelab";
in {
  # Allow HTTPS on VPN interface only
  networking.firewall.interfaces.${vpnInterface}.allowedTCPPorts = [443];

  # Use unstable ntfy-sh for template support (requires >= 2.14.0)
  services.ntfy-sh = {
    enable = true;
    package = pkgs.unstable.ntfy-sh;
    settings = {
      # Listen on localhost only, accessed via nginx proxy (defense in depth)
      listen-http = "127.0.0.1:${toString ntfyPort}";
      base-url = "https://${ntfyDomain}";

      # Authentication: deny all by default, require tokens for publishing
      auth-default-access = "deny-all";
      # Allow anyone to subscribe (read), but publishing requires auth
      # This allows the Android app to subscribe without auth
      auth-file = "/var/lib/ntfy-sh/user.db";

      # Template directory for custom webhook formatting
      template-dir = "/var/lib/ntfy-sh/templates";
    };
  };

  # Install custom Grafana template
  systemd.tmpfiles.rules = [
    "d /var/lib/ntfy-sh/templates 0755 ntfy-sh ntfy-sh -"
    "L+ /var/lib/ntfy-sh/templates/grafana.yml - - - - ${./ntfy/grafana.yml}"
  ];

  services.nginx = {
    enable = true;
    virtualHosts.${ntfyDomain} = {
      # Listen on all interfaces
      listenAddresses = ["0.0.0.0"];
      # Enable HTTPS with Let's Encrypt wildcard certificate
      forceSSL = true;
      useACMEHost = "${domain}";
      # Only allow access from Netbird VPN network
      extraConfig = ''
        allow 100.76.0.0/16;
        deny all;
      '';
      locations."/" = {
        proxyPass = "http://localhost:${toString ntfyPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}

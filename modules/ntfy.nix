{
  config,
  pkgs,
  ...
}: let
  ntfy = config.serviceConfig.ntfy;
  domain = "krejci.io";
  ntfyDomain = "${ntfy.subdomain}.${domain}";
  httpsPort = 443;
in {
  # Allow HTTPS on VPN interface only
  networking.firewall.interfaces."${ntfy.interface}".allowedTCPPorts = [httpsPort];

  # Use unstable ntfy-sh for template support (requires >= 2.14.0)
  services.ntfy-sh = {
    enable = true;
    package = pkgs.unstable.ntfy-sh;
    settings = {
      # Listen on 127.0.0.1 only, accessed via nginx proxy (defense in depth)
      listen-http = "127.0.0.1:${toString ntfy.port}";
      base-url = "https://${ntfyDomain}";

      # Authentication: read-only by default, publishing requires tokens
      auth-default-access = "read-only";
      # Grafana user can publish via token, everyone else can read
      auth-file = "/var/lib/ntfy-sh/user.db";

      # Template directory for custom webhook formatting
      template-dir = "/var/lib/ntfy-sh/templates";

      # Expose Prometheus metrics on 127.0.0.1 only
      metrics-listen-http = "127.0.0.1:${toString ntfy.metricsPort}";
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
        proxyPass = "http://127.0.0.1:${toString ntfy.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}

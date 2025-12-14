{
  config,
  pkgs,
  ...
}: let
  services = config.serviceConfig;
  host = config.hostConfig.self;
  ntfyDomain = "${services.ntfy.subdomain}.${services.global.domain}";
in {
  # Allow HTTPS on VPN interface only
  networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [services.https.port];

  # Use unstable ntfy-sh for template support (requires >= 2.14.0)
  services.ntfy-sh = {
    enable = true;
    package = pkgs.unstable.ntfy-sh;
    settings = {
      # Listen on 127.0.0.1 only, accessed via nginx proxy (defense in depth)
      listen-http = "127.0.0.1:${toString services.ntfy.port}";
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
      listenAddresses = [host.services.ntfy.ip];
      # Enable HTTPS with Let's Encrypt wildcard certificate
      forceSSL = true;
      useACMEHost = "${services.global.domain}";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString services.ntfy.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
    # Ntfy metrics via unified metrics proxy
    virtualHosts."metrics".locations."/metrics/ntfy".proxyPass = "http://127.0.0.1:9091/metrics";
  };
}

{ config, ... }:
let
  server_ip_address = "192.168.99.1";
  server_domain = "vpsfree.home";
  grafana_port = 3000;
in
{
  networking.firewall.interfaces."wg0".allowedTCPPorts = [ 9090 grafana_port 80 443 ];

  services.prometheus = {
    enable = true;
    retentionTime = "180d";
    listenAddress = server_ip_address;
    globalConfig.scrape_interval = "10s";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [
            "rpi4.home:9100"
            "vpsfree.home:9100"
            "thinkpad.home:9100"
            "optiplex.home:9100"
          ];
        }];
      }
    ];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = server_ip_address;
        http_port = grafana_port;
        domain = server_domain;
        root_url = "http://${server_domain}/grafana";
        serve_from_sub_path = true;
      };
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts.${config.services.grafana.settings.server.domain} = {
      # addSSL = true;
      # enableACME = true;
      listenAddresses = [ "${server_domain}" ];
      locations."/grafana/" = {
        proxyPass = "http://${server_domain}:${toString grafana_port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };

  # security.acme = {
  #   acceptTerms = true;
  #   defaults.email = "krejcijan@protonmail.com";
  # };
}

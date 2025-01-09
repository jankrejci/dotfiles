{ config, ... }:
{
  # networking.firewall.interfaces."wg0".allowedUDPPorts = [ 9090 ];
  networking.firewall.interfaces."wg0".allowedTCPPorts = [ 9090 3000 80 ];

  services.prometheus = {
    enable = true;
    retentionTime = "180d";
    listenAddress = "192.168.99.1";
    globalConfig.scrape_interval = "10s";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [
            "rpi4.home:9100"
            "vpsfree.home:9100"
          ];
        }];
      }
    ];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "192.168.99.1";
        http_port = 3000;
        domain = "vpsfree.home";
        root_url = "http://vpsfree.home/grafana";
        serve_from_sub_path = true;
      };
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts.${config.services.grafana.domain} = {
      # addSSL = true;
      # enableACME = true;
      listenAddresses = [ "192.168.99.1" ];
      locations."/grafana/" = {
        proxyPass = "http://192.168.99.1:3000";
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

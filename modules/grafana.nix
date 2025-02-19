{ config, hostConfig, ... }:
let
  serverIpAddress = "${hostConfig.ipAddress}";
  serverDomain = "${hostConfig.hostName}.home";
  grafanaPort = 3000;
in
{
  networking.firewall.interfaces."wg0".allowedTCPPorts = [ 9090 grafanaPort 80 443 ];

  services.prometheus = {
    enable = true;
    retentionTime = "180d";
    listenAddress = serverIpAddress;
    globalConfig.scrape_interval = "10s";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          # TODO generate targets with function
          targets = [
            "rpi4.home:9100"
            "vpsfree.home:9100"
            "thinkpad.home:9100"
            "optiplex.home:9100"
            "prusa.home:9100"
          ];
        }];
      }
    ];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = serverIpAddress;
        http_port = grafanaPort;
        domain = serverDomain;
        root_url = "http://${serverDomain}/grafana";
        serve_from_sub_path = true;
      };
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts.${config.services.grafana.settings.server.domain} = {
      # addSSL = true;
      # enableACME = true;
      listenAddresses = [ "${serverDomain}" ];
      locations."/grafana/" = {
        proxyPass = "http://${serverDomain}:${toString grafanaPort}";
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

{ config, hostConfig, ... }:
let
  domain = "vpn";
  serverIpAddress = "${hostConfig.ipAddress}";
  serverDomain = hostConfig.hostName + "." + domain;
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
            "rpi4.${domain}:9100"
            "vpsfree.${domain}:9100"
            "thinkpad.${domain}:9100"
            "optiplex.${domain}:9100"
            "prusa.${domain}:9100"
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
      listenAddresses = [ "${serverDomain}" ];
      locations."/grafana/" = {
        proxyPass = "http://${serverDomain}:${toString grafanaPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };

  services.grafana.provision.dashboards.settings = {
    apiVersion = 1;
    providers = [{
      name = "default";
      options.path = "/etc/grafana/dashboards";
    }];
  };

  environment.etc."grafana/dashboards/overview.json" = {
    source = ./grafana/overview.json;
    mode = "0644";
  };
}


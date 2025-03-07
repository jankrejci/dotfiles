{ config, lib, ... }:
let
  domain = "vpn";
  serverIpAddress = "${config.hosts.self.ipAddress}";
  serverDomain = config.hosts.self.hostName + "." + domain;
  grafanaPort = 3000;
in
{
  networking.firewall.interfaces."wg0".allowedTCPPorts = [ 9090 grafanaPort 80 443 ];

  services.prometheus = {
    enable = true;
    retentionTime = "180d";
    listenAddress = serverIpAddress;
    globalConfig.scrape_interval = "10s";
    scrapeConfigs = [{
      job_name = "node";
      static_configs = [{
        targets =
          let
            nodeExporterPort = "9100";
            makeTarget = hostName: hostConfig: hostName + "." + domain + ":" nodeExporterPort;
            # Only NixOS hosts are running the prometheus node exporter
            nixosHosts = lib.filterAttrs (_: hostConfig: hostConfig.kind == "nixos") config.hosts;
          in
          # Generate the list of targets
          lib.mapAttrsToList makeTarget nixosHosts;
      }];
    }];
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


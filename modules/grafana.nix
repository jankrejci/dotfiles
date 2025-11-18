{
  config,
  lib,
  ...
}: let
  domain = "krejci.io";
  serverDomain = config.hosts.self.hostName + "." + domain;
  grafanaPort = 3000;
in {
  # Allow Grafana, Prometheus, and Nginx on VPN interface
  networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [9090 grafanaPort 80 443];

  services.prometheus = {
    enable = true;
    retentionTime = "180d";
    # Listen on all interfaces, security enforced via firewall
    listenAddress = "0.0.0.0";
    globalConfig.scrape_interval = "10s";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = let
              nodeExporterPort = "9100";
              makeTarget = hostName: hostConfig: hostName + "." + domain + ":" + nodeExporterPort;
              # Only NixOS hosts are running the prometheus node exporter
              nixosHosts = lib.filterAttrs (_: hostConfig: hostConfig.kind == "nixos") config.hosts;
            in
              # Generate the list of targets
              lib.mapAttrsToList makeTarget nixosHosts;
          }
        ];
      }
    ];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        # Listen on all interfaces, security enforced via firewall
        http_addr = "0.0.0.0";
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
      # Listen on all interfaces, security enforced via firewall
      listenAddresses = ["0.0.0.0"];
      locations."/grafana/" = {
        # Use localhost since Grafana is on the same host as Nginx
        proxyPass = "http://localhost:${toString grafanaPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };

  services.grafana.provision.dashboards.settings = {
    apiVersion = 1;
    providers = [
      {
        name = "default";
        options.path = "/etc/grafana/dashboards";
      }
    ];
  };

  environment.etc."grafana/dashboards/overview.json" = {
    source = ./grafana/overview.json;
    mode = "0644";
  };
}

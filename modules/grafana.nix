{
  config,
  lib,
  ...
}: let
  domain = "krejci.io";
  serverDomain = config.hosts.self.hostName + "." + domain;
  grafanaPort = 3000;
  vpnIp = "100.76.208.183";
  vpnInterface = "nb-homelab";
in {
  # Allow HTTPS on VPN interface
  networking.firewall.interfaces.${vpnInterface}.allowedTCPPorts = [443];

  services.prometheus = {
    enable = true;
    retentionTime = "180d";
    # Listen on localhost only, accessed via nginx proxy (defense in depth)
    listenAddress = "127.0.0.1";
    # Serve from subpath /prometheus/
    extraFlags = ["--web.external-url=https://${serverDomain}/prometheus" "--web.route-prefix=/"];
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
        # Listen on localhost only, accessed via nginx proxy (defense in depth)
        http_addr = "127.0.0.1";
        http_port = grafanaPort;
        domain = serverDomain;
        root_url = "https://${serverDomain}/grafana";
        serve_from_sub_path = true;
      };
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts.${config.services.grafana.settings.server.domain} = {
      listen = [
        {
          addr = vpnIp;
          port = 443;
          ssl = true;
        }
      ];
      # Enable HTTPS with Let's Encrypt wildcard certificate
      forceSSL = true;
      useACMEHost = "${domain}";
      locations."/grafana/" = {
        # Use localhost since Grafana is on the same host as Nginx
        proxyPass = "http://localhost:${toString grafanaPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
      locations."/prometheus/" = {
        # Proxy to Prometheus (localhost only)
        proxyPass = "http://localhost:9090";
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

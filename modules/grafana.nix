{
  config,
  lib,
  ...
}: let
  domain = "krejci.io";
  serverDomain = "grafana." + domain;
  grafanaPort = 3000;
  vpnInterface = "nb-homelab";
  immichApiMetricsPort = 8081;
  immichMicroservicesMetricsPort = 8082;
in {
  # Allow HTTPS on VPN interface
  networking.firewall.interfaces.${vpnInterface}.allowedTCPPorts = [443];

  services.prometheus = {
    enable = true;
    retentionTime = "180d";
    # Listen on localhost only, accessed via nginx proxy (defense in depth)
    listenAddress = "127.0.0.1";
    # Serve from subpath /prometheus/
    extraFlags = ["--web.external-url=https://${serverDomain}/prometheus" "--web.route-prefix=/prometheus"];
    globalConfig.scrape_interval = "10s";
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{targets = ["localhost:9090"];}];
        metrics_path = "/prometheus/metrics";
      }
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
      {
        job_name = "immich-api";
        static_configs = [
          {
            targets = ["localhost:${toString immichApiMetricsPort}"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "immich-microservices";
        static_configs = [
          {
            targets = ["localhost:${toString immichMicroservicesMetricsPort}"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "ntfy";
        static_configs = [
          {
            targets = ["localhost:9091"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "postgres";
        static_configs = [
          {
            targets = ["localhost:9187"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "redis";
        static_configs = [
          {
            targets = ["localhost:9121"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "nginx";
        static_configs = [
          {
            targets = ["localhost:9113"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "wireguard";
        static_configs = [
          {
            targets = ["localhost:9586"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
    ];
  };

  systemd.services.grafana = {
    serviceConfig.EnvironmentFile = "/var/lib/grafana/secrets/ntfy-token-env";
    restartTriggers = [
      (builtins.toJSON config.services.grafana.settings)
      (builtins.toJSON config.services.grafana.provision.datasources.settings)
      (builtins.toJSON config.services.grafana.provision.dashboards.settings)
      (builtins.toJSON config.services.grafana.provision.alerting.rules.path)
      (builtins.toJSON config.services.grafana.provision.alerting.contactPoints.settings)
      (builtins.toJSON config.services.grafana.provision.alerting.policies.settings)
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
        root_url = "https://${serverDomain}";
      };
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts.${serverDomain} = {
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

  services.grafana.provision.datasources.settings = {
    apiVersion = 1;
    datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        access = "proxy";
        url = "http://localhost:9090/prometheus";
        isDefault = true;
        uid = "prometheus";
      }
    ];
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

  services.grafana.provision.alerting = {
    rules.path = ./grafana/alerts;

    contactPoints.settings = {
      apiVersion = 1;
      contactPoints = [
        {
          orgId = 1;
          name = "ntfy";
          receivers = [
            {
              uid = "ntfy-webhook";
              type = "webhook";
              disableResolveMessage = false;
              settings = {
                url = "http://localhost:2586/grafana-alerts?template=grafana";
                httpMethod = "POST";
                authorization_scheme = "Bearer";
                authorization_credentials = "$NTFY_TOKEN";
              };
            }
          ];
        }
      ];
    };

    policies.settings = {
      apiVersion = 1;
      policies = [
        {
          orgId = 1;
          receiver = "ntfy";
          group_by = ["alertname"];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "12h";
        }
      ];
    };
  };

  environment.etc."grafana/dashboards".source = ./grafana/dashboards;
}

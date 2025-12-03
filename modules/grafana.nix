{
  config,
  lib,
  ...
}: let
  services = config.serviceConfig;
  domain = "krejci.io";
  serverDomain = "${services.grafana.subdomain}.${domain}";
  httpsPort = 443;
in {
  # Allow HTTPS on VPN interface
  networking.firewall.interfaces."${services.grafana.interface}".allowedTCPPorts = [httpsPort];

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
        # 127.0.0.1 only - accessed via nginx proxy (defense in depth)
        http_addr = "127.0.0.1";
        http_port = services.grafana.port;
        domain = serverDomain;
        root_url = "https://${serverDomain}";
      };
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts.${serverDomain} = {
      listenAddresses = ["0.0.0.0"];
      forceSSL = true;
      useACMEHost = "${domain}";
      # Only allow access from Netbird VPN network
      extraConfig = ''
        allow 100.76.0.0/16;
        deny all;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString services.grafana.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
      # Prometheus UI accessible at /prometheus/
      locations."/prometheus/" = {
        proxyPass = "http://127.0.0.1:${toString services.prometheus.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };

  # Datasources are provided by prometheus.nix and loki.nix modules
  services.grafana.provision.datasources.settings.apiVersion = 1;

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
                url = "http://127.0.0.1:${toString services.ntfy.port}/grafana-alerts?template=grafana";
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

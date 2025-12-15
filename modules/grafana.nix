# Grafana monitoring dashboard with homelab enable flag
{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.grafana;
  services = config.homelab.services;
  host = config.homelab.host;
  domain = services.global.domain;
  serverDomain = "${services.grafana.subdomain}.${domain}";
in {
  options.homelab.grafana = {
    # Default true preserves existing behavior where importing the module enables it.
    # Will change to false in Phase 4 when hosts explicitly set enable flags.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Grafana monitoring dashboard";
    };
  };

  config = lib.mkIf cfg.enable {
    # Allow HTTPS on VPN interface
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

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
      settings.server = {
        # 127.0.0.1 only - accessed via nginx proxy (defense in depth)
        http_addr = "127.0.0.1";
        http_port = services.grafana.port;
        inherit domain;
        root_url = "https://${serverDomain}";
      };
    };

    # Wait for services interface before binding
    systemd.services.nginx.after = ["sys-subsystem-net-devices-services.device"];

    services.nginx = {
      enable = true;
      virtualHosts.${serverDomain} = {
        listenAddresses = [host.services.grafana.ip];
        forceSSL = true;
        useACMEHost = domain;
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

    services.grafana.provision.datasources.settings = {
      apiVersion = 1;
      datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:${toString services.prometheus.port}/prometheus";
          isDefault = true;
          # Fixed UID for dashboard references (see CLAUDE.md)
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
  };
}

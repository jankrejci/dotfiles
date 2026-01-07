# Grafana monitoring dashboard with homelab enable flag
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.grafana;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  serverDomain = "${cfg.subdomain}.${domain}";
in {
  options.homelab.grafana = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Grafana monitoring dashboard";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for Grafana web interface";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "grafana";
      description = "Subdomain for Grafana";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [serverDomain];

    # Allow HTTPS on VPN interface
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

    systemd.services.grafana = {
      restartTriggers = [
        (builtins.toJSON config.services.grafana.settings)
        (builtins.toJSON config.services.grafana.provision.datasources.settings)
        (builtins.toJSON config.services.grafana.provision.dashboards.settings)
        # Restart when dashboard files change
        config.environment.etc."grafana/dashboards".source
      ];
    };

    services.grafana = {
      enable = true;
      # Infinity plugin for querying external APIs like Binance
      declarativePlugins = with pkgs.grafanaPlugins; [
        yesoreyeram-infinity-datasource
      ];
      settings.server = {
        # 127.0.0.1 only - accessed via nginx proxy (defense in depth)
        http_addr = "127.0.0.1";
        http_port = cfg.port;
        inherit domain;
        root_url = "https://${serverDomain}";
      };
    };

    services.nginx.virtualHosts.${serverDomain} = {
      listenAddresses = [cfg.ip];
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
      # Prometheus UI accessible at /prometheus/
      locations."/prometheus/" = {
        proxyPass = "http://127.0.0.1:${toString config.homelab.prometheus.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    services.grafana.provision.datasources.settings = {
      apiVersion = 1;
      datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:${toString config.homelab.prometheus.port}/prometheus";
          isDefault = true;
          # Fixed UID for dashboard references
          uid = "prometheus";
        }
        {
          name = "Binance";
          type = "yesoreyeram-infinity-datasource";
          access = "proxy";
          # Fixed UID for dashboard references
          uid = "binance";
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

    environment.etc."grafana/dashboards".source = ../assets/grafana/dashboards;

    # Image renderer for PNG exports and alert notifications
    # Port 8083 to avoid conflict with immich on 8081-8082
    services.grafana-image-renderer = {
      enable = true;
      provisionGrafana = true;
      settings.server.addr = "127.0.0.1:8083";
    };
  };
}

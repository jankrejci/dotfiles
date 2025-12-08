{lib, ...}:
with lib; {
  options.serviceConfig = mkOption {
    description = "Centralized service configuration";
    type = types.attrsOf (types.submodule {
      options = {
        port = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = "Main service port";
        };

        subdomain = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Subdomain (e.g., 'grafana' for grafana.domain)";
        };

        metricsPort = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = "Prometheus metrics port";
        };

        interface = mkOption {
          type = types.str;
          default = "nb-homelab";
          description = "Network interface for firewall rules";
        };
      };
    });
  };

  config.serviceConfig = {
    # Core services
    grafana = {
      port = 3000;
      subdomain = "grafana";
    };

    prometheus = {
      port = 9090;
    };

    loki = {
      port = 3100;
    };

    promtail = {
      port = 9080;
    };

    # Application services
    immich = {
      port = 2283;
      subdomain = "immich";
      metricsPort = 8081;
    };

    immich-microservices = {
      port = 2283;
      metricsPort = 8082;
    };

    ntfy = {
      port = 2586;
      subdomain = "ntfy";
      metricsPort = 9091;
    };

    jellyfin = {
      port = 8096;
      subdomain = "jellyfin";
    };

    octoprint = {
      port = 5000;
      subdomain = "octoprint";
    };

    immich-public-proxy = {
      port = 2283;
      subdomain = "share";
      interface = "venet0";
    };

    # Prometheus exporters
    node-exporter = {
      metricsPort = 9100;
    };

    postgres = {
      metricsPort = 9187;
    };

    redis = {
      metricsPort = 9121;
    };

    nginx = {
      metricsPort = 9113;
    };

    wireguard = {
      metricsPort = 9586;
    };
  };
}

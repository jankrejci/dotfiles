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

        domain = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Base domain for services";
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
    # Global configuration
    global = {
      domain = "krejci.io";
    };

    https = {
      port = 443;
    };

    metrics = {
      port = 9999;
    };

    netbird = {
      interface = "nb-homelab";
    };

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
    };

    ntfy = {
      port = 2586;
      subdomain = "ntfy";
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
  };
}

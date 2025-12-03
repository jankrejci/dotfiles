{
  config,
  lib,
  ...
}: let
  service = config.serviceConfig;
  domain = "krejci.io";
in {
  services.prometheus = {
    enable = true;
    # Keep metrics for 6 months
    retentionTime = "180d";
    # 127.0.0.1 only - accessed via nginx proxy (defense in depth)
    listenAddress = "127.0.0.1";
    # Serve from subpath /prometheus/ (shares domain with Grafana)
    extraFlags = ["--web.external-url=https://${service.grafana.subdomain}.${domain}/prometheus" "--web.route-prefix=/prometheus"];
    globalConfig.scrape_interval = "10s";
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{targets = ["127.0.0.1:${toString service.prometheus.port}"];}];
        metrics_path = "/prometheus/metrics";
      }
      {
        # Node exporter from all NixOS hosts in the fleet
        job_name = "node";
        static_configs = [
          {
            targets = let
              makeTarget = hostName: _: "${hostName}.${domain}:${toString service.node-exporter.metricsPort}";
              nixosHosts = lib.filterAttrs (_: hostConfig: hostConfig.kind == "nixos") config.hostConfig;
            in
              lib.mapAttrsToList makeTarget nixosHosts;
          }
        ];
      }
      {
        job_name = "immich-api";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString service.immich.metricsPort}"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "immich-microservices";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString service.immich-microservices.metricsPort}"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "ntfy";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString service.ntfy.metricsPort}"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "postgres";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString service.postgres.metricsPort}"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "redis";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString service.redis.metricsPort}"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "nginx";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString service.nginx.metricsPort}"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
      {
        job_name = "wireguard";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString service.wireguard.metricsPort}"];
            labels = {host = "thinkcenter";};
          }
        ];
      }
    ];
  };

  # Prometheus datasource for Grafana
  services.grafana.provision.datasources.settings.datasources = [
    {
      name = "Prometheus";
      type = "prometheus";
      access = "proxy";
      url = "http://127.0.0.1:${toString service.prometheus.port}/prometheus";
      isDefault = true;
      # Fixed UID for dashboard references (see CLAUDE.md)
      uid = "prometheus";
    }
  ];
}

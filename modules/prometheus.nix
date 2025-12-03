{
  config,
  lib,
  ...
}: let
  domain = "krejci.io";
  serverDomain = "grafana." + domain;
  immichApiMetricsPort = 8081;
  immichMicroservicesMetricsPort = 8082;
in {
  services.prometheus = {
    enable = true;
    # Keep metrics for 6 months
    retentionTime = "180d";
    # Localhost only - accessed via nginx proxy (defense in depth)
    listenAddress = "127.0.0.1";
    # Serve from subpath /prometheus/ (shares domain with Grafana)
    extraFlags = ["--web.external-url=https://${serverDomain}/prometheus" "--web.route-prefix=/prometheus"];
    globalConfig.scrape_interval = "10s";
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{targets = ["localhost:9090"];}];
        metrics_path = "/prometheus/metrics";
      }
      {
        # Node exporter from all NixOS hosts in the fleet
        job_name = "node";
        static_configs = [
          {
            targets = let
              nodeExporterPort = "9100";
              makeTarget = hostName: hostConfig: hostName + "." + domain + ":" + nodeExporterPort;
              nixosHosts = lib.filterAttrs (_: hostConfig: hostConfig.kind == "nixos") config.hosts;
            in
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

  # Prometheus datasource for Grafana
  services.grafana.provision.datasources.settings.datasources = [
    {
      name = "Prometheus";
      type = "prometheus";
      access = "proxy";
      url = "http://localhost:9090/prometheus";
      isDefault = true;
      # Fixed UID for dashboard references (see CLAUDE.md)
      uid = "prometheus";
    }
  ];
}

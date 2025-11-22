{
  config,
  lib,
  ...
}: let
  domain = "krejci.io";
  serverDomain = config.hosts.self.hostName + "." + domain;
  grafanaPort = 3000;
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
    rules = [
      ''
        groups:
          - name: immich
            rules:
              - alert: ImmichDown
                expr: up{job=~"immich-.*"} == 0
                for: 5m
                annotations:
                  summary: "Immich service {{ $labels.job }} is down"

          - name: backup
            rules:
              - alert: BorgBackupFailed
                expr: node_systemd_unit_state{name=~"borgbackup-job-.*",state="failed"} == 1
                for: 1m
                annotations:
                  summary: "Borg backup job {{ $labels.name }} failed on {{ $labels.instance }}"

              - alert: BorgBackupNotRunning
                expr: time() - node_systemd_timer_last_trigger_seconds{name=~"borgbackup-job-.*"} > 86400
                for: 1h
                annotations:
                  summary: "Borg backup {{ $labels.name }} has not run in 24h on {{ $labels.instance }}"
      ''
    ];
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
      {
        job_name = "immich-api";
        static_configs = [
          {
            targets = ["thinkcenter.${domain}:8081"];
          }
        ];
      }
      {
        job_name = "immich-microservices";
        static_configs = [
          {
            targets = ["thinkcenter.${domain}:8082"];
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

  services.grafana.provision.datasources.settings = {
    apiVersion = 1;
    datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        access = "proxy";
        url = "http://localhost:9090";
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

  environment.etc."grafana/dashboards/overview.json" = {
    source = ./grafana/overview.json;
    mode = "0644";
  };
}

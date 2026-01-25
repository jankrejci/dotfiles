# Prometheus monitoring stack
#
# Architecture:
# - Prometheus scrapes metrics from all nixos hosts via VPN
# - Alertmanager routes alerts to ntfy with custom templates
# - Metrics exposed via nginx proxy at /metrics/prometheus
#
# Scrape target discovery:
# - Each service module registers homelab.scrapeTargets
# - This module collects targets from all nixos hosts
# - Targets are grouped by job and scraped via {host}.nb.krejci.io:9999
#
# Alert aggregation:
# - Each service module registers homelab.alerts
# - This module collects alerts from all nixos hosts
# - Alerts must have type label (host or service) for correct routing
#
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.homelab.prometheus;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  peerDomain = global.peerDomain;
  metricsPort = toString services.metrics.port;
in {
  options.homelab.prometheus = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Prometheus metrics collection";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for Prometheus server";
    };
  };

  options.homelab.alertmanager = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 9093;
      description = "Port for Alertmanager";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ntfy token for alertmanager notifications
    age.secrets.ntfy-token = {
      rekeyFile = ../secrets/ntfy-token.age;
      owner = "prometheus";
    };

    services.prometheus = {
      enable = true;
      # Keep metrics for 6 months
      retentionTime = "180d";
      # 127.0.0.1 only - accessed via nginx proxy (defense in depth)
      listenAddress = "127.0.0.1";
      # Serve from subpath /prometheus/ (shares domain with Grafana)
      extraFlags = [
        "--web.external-url=https://${config.homelab.grafana.subdomain}.${domain}/prometheus"
        "--web.route-prefix=/prometheus"
        "--web.enable-admin-api"
      ];
      globalConfig.scrape_interval = "10s";
      # Scrape configs aggregated from homelab.scrapeTargets across all nixos hosts.
      # Each service module registers its scrape target, prometheus collects them all.
      scrapeConfigs = let
        allConfigs = inputs.self.nixosConfigurations;

        # Filter to nixos hosts only, excluding installer ISO
        nixosHostNames = lib.attrNames (
          lib.filterAttrs (_: h: (h.kind or "nixos") == "nixos") config.homelab.hosts
        );

        # Collect targets from all hosts, attach hostName to each
        allTargets = lib.flatten (
          map (
            name:
              map (target: target // {hostName = name;})
              (allConfigs.${name}.config.homelab.scrapeTargets or [])
          )
          nixosHostNames
        );

        # Group by job name so same job from multiple hosts becomes one scrape config
        targetsByJob = lib.groupBy (t: t.job) allTargets;

        # All targets scraped via VPN domain and metrics proxy port
        mkTarget = t: "${t.hostName}.${peerDomain}:${metricsPort}";
      in
        lib.mapAttrsToList (jobName: targets: {
          job_name = jobName;
          metrics_path = (builtins.head targets).metricsPath;
          static_configs =
            map (t: {
              targets = [(mkTarget t)];
              labels = {host = t.hostName;};
            })
            targets;
        })
        targetsByJob;

      # Point Prometheus to Alertmanager
      alertmanagers = [
        {
          static_configs = [
            {targets = ["127.0.0.1:${toString config.homelab.alertmanager.port}"];}
          ];
        }
      ];
    };

    # Alertmanager sends directly to ntfy using custom templates
    services.prometheus.alertmanager = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = config.homelab.alertmanager.port;
      configuration = {
        # Alertmanager routing tree:
        # - Alerts must have type label (host or service) to route correctly
        # - Alerts without type label fall through to ntfy-default
        # - Oneshot alerts (oneshot=true) get 1-year repeat interval
        # - More specific routes must come first to match correctly
        route = {
          receiver = "ntfy-default";
          group_by = ["alertname"];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "12h";
          routes = [
            # Oneshot routes first - suppress repeat notifications for persistent alerts
            {
              matchers = ["type=\"host\"" "oneshot=\"true\""];
              receiver = "ntfy-host";
              repeat_interval = "8760h";
            }
            {
              matchers = ["type=\"service\"" "oneshot=\"true\""];
              receiver = "ntfy-service";
              repeat_interval = "8760h";
            }
            # Regular routes for alerts without oneshot label
            {
              matchers = ["type=\"host\""];
              receiver = "ntfy-host";
            }
            {
              matchers = ["type=\"service\""];
              receiver = "ntfy-service";
            }
          ];
        };
        # Receivers send alerts to ntfy with different templates:
        # - ntfy-host: host down alerts with hostname in title
        # - ntfy-service: service alerts with service name in title
        # - ntfy-default: fallback for misconfigured alerts
        # Templates are defined in assets/ntfy/*.yml
        receivers = let
          mkReceiver = name: template: {
            inherit name;
            webhook_configs = [
              {
                url = "http://127.0.0.1:${toString config.homelab.ntfy.port}/grafana-alerts?template=${template}";
                send_resolved = true;
                http_config = {
                  authorization = {
                    type = "Bearer";
                    credentials_file = config.age.secrets.ntfy-token.path;
                  };
                };
              }
            ];
          };
        in [
          (mkReceiver "ntfy-host" "prometheus-host")
          (mkReceiver "ntfy-service" "prometheus-service")
          (mkReceiver "ntfy-default" "default")
        ];
      };
    };

    # Prometheus metrics via nginx proxy
    services.nginx.virtualHosts."metrics".locations."/metrics/prometheus".proxyPass = "http://127.0.0.1:${toString cfg.port}/prometheus/metrics";

    homelab.scrapeTargets = [
      {
        job = "prometheus";
        metricsPath = "/metrics/prometheus";
      }
    ];

    # Alert rules aggregated from homelab.alerts across all nixos hosts.
    # Each service module registers its alerts, prometheus collects them all.
    # Alerts are grouped by category name for organization in the rules file.
    services.prometheus.rules = let
      localAlerts = config.homelab.alerts;

      # Collect alerts from other nixos hosts
      allConfigs = inputs.self.nixosConfigurations;
      otherHostNames =
        lib.filter
        (name: name != config.homelab.host.hostName)
        (lib.attrNames (lib.filterAttrs (_: h: (h.kind or "nixos") == "nixos") config.homelab.hosts));
      remoteAlerts = lib.foldAttrs (a: b: a ++ b) [] (
        map (name: allConfigs.${name}.config.homelab.alerts or {}) otherHostNames
      );

      # Merge local and remote alerts by category
      allAlerts = lib.foldAttrs (a: b: a ++ b) [] [localAlerts remoteAlerts];

      # Convert to prometheus rule groups format
      alertGroups =
        lib.mapAttrsToList (name: rules: {
          inherit name rules;
        })
        allAlerts;
    in [
      (builtins.toJSON {
        groups = alertGroups;
      })
    ];

    # Health check
    homelab.healthChecks = [
      {
        name = "Prometheus";
        script = pkgs.writeShellApplication {
          name = "health-check-prometheus";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet prometheus.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

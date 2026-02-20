# Prometheus monitoring stack
#
# Architecture:
# - Prometheus scrapes metrics from all nixos hosts via VPN
# - Alertmanager routes alerts via ntfy webhooks
# - Own domain with nginx reverse proxy
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
  promDomain = "${cfg.subdomain}.${domain}";
in {
  options.homelab.prometheus = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Prometheus metrics collection";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "prometheus";
      description = "Subdomain for Prometheus UI";
    };

    port = {
      prometheus = lib.mkOption {
        type = lib.types.port;
        description = "Port for Prometheus server";
      };

      alertmanager = lib.mkOption {
        type = lib.types.port;
        description = "Port for Alertmanager";
      };
    };

    watchdog = lib.mkEnableOption "watchdog monitoring for this prometheus instance";

    retention = lib.mkOption {
      type = lib.types.str;
      default = "360d";
      description = "How long to keep metrics data";
    };
  };

  config = lib.mkIf cfg.enable (let
    myHostName = config.homelab.host.hostName;
  in {
    assertions = [
      {
        assertion = config.homelab.ntfy.enable;
        message = "homelab.prometheus requires homelab.ntfy.enable = true for alertmanager notifications";
      }
    ];

    # Ntfy token for alertmanager webhook authentication
    age.secrets.ntfy-token = {
      rekeyFile = ../secrets/ntfy-token.age;
      owner = "prometheus";
    };

    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [promDomain];

    # Allow HTTPS on VPN interface only
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

    services.prometheus = {
      enable = true;
      retentionTime = cfg.retention;
      # 127.0.0.1 only - accessed via nginx proxy (defense in depth)
      listenAddress = "127.0.0.1";
      extraFlags = ["--web.enable-admin-api"];
      globalConfig.scrape_interval = "10s";
      # Scrape configs aggregated from homelab.scrapeTargets across all nixos hosts.
      # Each service module registers its scrape target, prometheus collects them all.
      scrapeConfigs = let
        allConfigs = inputs.self.nixosConfigurations;

        # Scrape all nixos hosts
        nixosHostNames = lib.attrNames (
          lib.filterAttrs (
            _: host:
              (host.kind or "nixos") == "nixos"
          )
          config.homelab.hosts
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
            {targets = ["127.0.0.1:${toString cfg.port.alertmanager}"];}
          ];
        }
      ];
    };

    # Alertmanager routes alerts via ntfy webhooks with template-based routing
    services.prometheus.alertmanager = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = cfg.port.alertmanager;
      configuration = {
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
        receivers = let
          mkReceiver = name: template: {
            inherit name;
            webhook_configs = [
              {
                url = "http://127.0.0.1:${toString config.homelab.ntfy.port.ntfy}/grafana-alerts?template=${template}";
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

    services.nginx.virtualHosts.${promDomain} = {
      listenAddresses = [cfg.ip];
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port.prometheus}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    # Prometheus metrics via unified metrics proxy
    services.nginx.virtualHosts."metrics".locations."/metrics/prometheus".proxyPass = "http://127.0.0.1:${toString cfg.port.prometheus}/metrics";

    homelab.scrapeTargets = [
      {
        job = "prometheus";
        metricsPath = "/metrics/prometheus";
      }
    ];

    # Register with external watchdog when enabled
    homelab.watchdogTargets = lib.optionals cfg.watchdog [
      {
        job = "prometheus";
        host = myHostName;
      }
    ];

    # Alert rules aggregated from homelab.alerts across all nixos hosts.
    # Each service module registers its alerts, prometheus collects them all.
    # Alerts are grouped by category name for organization in the rules file.
    services.prometheus.rules = let
      localAlerts = config.homelab.alerts;

      # Collect alerts from all other nixos hosts
      allConfigs = inputs.self.nixosConfigurations;
      otherHostNames =
        lib.filter
        (name: name != myHostName)
        (lib.attrNames (lib.filterAttrs (
            _: host:
              (host.kind or "nixos") == "nixos"
          )
          config.homelab.hosts));
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

    homelab.dashboardEntries = [
      {
        name = "Prometheus";
        url = "https://${promDomain}";
        icon = ../assets/dashboard-icons/prometheus.svg;
      }
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
  });
}

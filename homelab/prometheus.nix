# Prometheus monitoring stack
#
# Architecture:
# - Prometheus scrapes metrics from hosts listed in scrapedBy via VPN
# - Alertmanager routes alerts via ntfy (primary) or email (secondary)
# - Metrics exposed via nginx proxy at /metrics/prometheus
#
# Scrape target discovery:
# - Each service module registers homelab.scrapeTargets
# - This module collects targets from hosts where scrapedBy includes this host
# - Targets are grouped by job and scraped via {host}.nb.krejci.io:9999
#
# Alert aggregation:
# - Each service module registers homelab.alerts
# - This module collects alerts from hosts in this instance's scrapedBy scope
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

    watchdog = lib.mkEnableOption "watchdog monitoring for this prometheus instance";

    retention = lib.mkOption {
      type = lib.types.str;
      default = "360d";
      description = "How long to keep metrics data";
    };

    alerting = {
      method = lib.mkOption {
        type = lib.types.enum ["ntfy" "email"];
        default = "ntfy";
        description = "How alertmanager delivers notifications";
      };

      email = {
        # Standard SMTP term for the relay that handles outbound mail
        smarthost = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1:1025";
          description = "SMTP smarthost in host:port format";
        };

        from = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Sender email address";
        };

        to = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Recipient email address";
        };
      };
    };
  };

  options.homelab.alertmanager = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 9093;
      description = "Port for Alertmanager";
    };
  };

  config = lib.mkIf cfg.enable (let
    myHostName = config.homelab.host.hostName;
  in {
    # Ntfy token for alertmanager webhook authentication
    age.secrets.ntfy-token = lib.mkIf (cfg.alerting.method == "ntfy") {
      rekeyFile = ../secrets/ntfy-token.age;
      owner = "prometheus";
    };

    # SMTP password for Protonmail Bridge authentication
    age.secrets.smtp-token = lib.mkIf (cfg.alerting.method == "email") {
      rekeyFile = ../secrets/smtp-token.age;
      owner = "prometheus";
    };

    services.prometheus = {
      enable = true;
      retentionTime = cfg.retention;
      # 127.0.0.1 only - accessed via nginx proxy (defense in depth)
      listenAddress = "127.0.0.1";
      # Subpath only when sharing domain with Grafana.
      # Assumes Grafana runs on the same machine as Prometheus.
      extraFlags =
        lib.optionals config.homelab.grafana.enable [
          "--web.external-url=https://${config.homelab.grafana.subdomain}.${domain}/prometheus"
          "--web.route-prefix=/prometheus"
        ]
        ++ ["--web.enable-admin-api"];
      globalConfig.scrape_interval = "10s";
      # Scrape configs aggregated from homelab.scrapeTargets across all nixos hosts.
      # Each service module registers its scrape target, prometheus collects them all.
      scrapeConfigs = let
        allConfigs = inputs.self.nixosConfigurations;

        # Only scrape hosts that list this prometheus instance in scrapedBy
        nixosHostNames = lib.attrNames (
          lib.filterAttrs (
            _: host:
              (host.kind or "nixos")
              == "nixos"
              && builtins.elem myHostName (host.scrapedBy or [])
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
            {targets = ["127.0.0.1:${toString config.homelab.alertmanager.port}"];}
          ];
        }
      ];
    };

    # Alertmanager routes alerts via ntfy webhooks or email depending on method
    services.prometheus.alertmanager = let
      # Ntfy webhook alertmanager config with template-based routing
      ntfyConfig = {
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

      # Email alertmanager config for secondary prometheus via Protonmail Bridge
      emailConfig = {
        global = {
          smtp_smarthost = cfg.alerting.email.smarthost;
          smtp_from = cfg.alerting.email.from;
          smtp_auth_username = cfg.alerting.email.from;
          smtp_auth_password_file = config.age.secrets.smtp-token.path;
          # Protonmail Bridge on localhost handles TLS upstream
          smtp_require_tls = false;
        };
        route = {
          receiver = "email";
          group_by = ["alertname"];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "12h";
        };
        receivers = [
          {
            name = "email";
            email_configs = [{to = cfg.alerting.email.to;}];
          }
        ];
      };
    in {
      enable = true;
      listenAddress = "127.0.0.1";
      port = config.homelab.alertmanager.port;
      configuration =
        if cfg.alerting.method == "ntfy"
        then ntfyConfig
        else emailConfig;
    };

    # Prometheus metrics via nginx proxy
    services.nginx.virtualHosts."metrics".locations."/metrics/prometheus".proxyPass =
      if config.homelab.grafana.enable
      then "http://127.0.0.1:${toString cfg.port}/prometheus/metrics"
      else "http://127.0.0.1:${toString cfg.port}/metrics";

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

      # Collect alerts from other hosts in this instance's scrapedBy scope
      allConfigs = inputs.self.nixosConfigurations;
      otherHostNames =
        lib.filter
        (name: name != myHostName)
        (lib.attrNames (lib.filterAttrs (
            _: host:
              (host.kind or "nixos")
              == "nixos"
              && builtins.elem myHostName (host.scrapedBy or [])
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

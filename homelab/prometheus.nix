# Prometheus monitoring with homelab enable flag
{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.prometheus;
  global = config.homelab.global;
  services = config.homelab.services;
  hosts = config.homelab.hosts;
  domain = global.domain;
  peerDomain = global.peerDomain;
  metricsPort = toString services.metrics.port;

  # Ntfy credentials file for alertmanager
  ntfyCredentialsFile = "/var/lib/alertmanager/ntfy-token.txt";
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
      ];
      globalConfig.scrape_interval = "10s";
      scrapeConfigs = [
        {
          job_name = "prometheus";
          static_configs = [{targets = ["127.0.0.1:${toString cfg.port}"];}];
          metrics_path = "/prometheus/metrics";
        }
        {
          # Node exporter from all NixOS hosts in the fleet
          job_name = "node";
          metrics_path = "/metrics/node";
          static_configs = [
            {
              targets = let
                makeTarget = hostName: _: "${hostName}.${peerDomain}:${metricsPort}";
                # Filter out "self" reference injected by flake.nix
                nixosHosts = lib.filterAttrs (name: hostConfig: name != "self" && (hostConfig.kind or "nixos") == "nixos") hosts;
              in
                lib.mapAttrsToList makeTarget nixosHosts;
            }
          ];
        }
        {
          job_name = "immich";
          metrics_path = "/metrics/immich";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${metricsPort}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "immich-microservices";
          metrics_path = "/metrics/immich-microservices";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${metricsPort}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "ntfy";
          metrics_path = "/metrics/ntfy";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${metricsPort}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "postgres";
          metrics_path = "/metrics/postgres";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${metricsPort}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "redis";
          metrics_path = "/metrics/redis";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${metricsPort}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "nginx";
          metrics_path = "/metrics/nginx";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${metricsPort}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "wireguard";
          metrics_path = "/metrics/wireguard";
          static_configs = [
            {
              targets = ["thinkcenter.${peerDomain}:${metricsPort}"];
              labels = {host = "thinkcenter";};
            }
          ];
        }
        {
          job_name = "octoprint";
          metrics_path = "/metrics/octoprint";
          static_configs = [
            {
              targets = ["prusa.${peerDomain}:${metricsPort}"];
              labels = {host = "prusa";};
            }
          ];
        }
      ];

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
        route = {
          receiver = "ntfy-default";
          group_by = ["alertname"];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "12h";
          routes = let
            # Sub-route for oneshot alerts - suppresses repeat notifications
            oneshotRoute = {
              match = {oneshot = "true";};
              repeat_interval = "8760h";
            };
          in [
            {
              match = {type = "host";};
              receiver = "ntfy-host";
              routes = [oneshotRoute];
            }
            {
              match = {type = "service";};
              receiver = "ntfy-service";
              routes = [oneshotRoute];
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
                    credentials_file = ntfyCredentialsFile;
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

    # Alert rules - will be populated from homelab.alerts
    services.prometheus.rules = [];
  };
}

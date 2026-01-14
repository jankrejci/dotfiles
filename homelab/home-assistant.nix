# Home Assistant with MQTT integration
#
# Architecture: HA receives device data from zigbee2mqtt via MQTT broker,
# stores history in PostgreSQL, and exposes metrics to Prometheus. All traffic
# flows through localhost except the nginx reverse proxy on VPN interface.
#
# Zigbee stack:
#   ZBDongle-E (coordinator) -> zigbee2mqtt -> mosquitto MQTT -> Home Assistant
#
# Data flow:
#   Devices -> HA -> PostgreSQL recorder (30 day retention)
#           -> HA -> /api/prometheus -> Prometheus scraper
#
# Secrets: Location data and API keys go in /var/lib/hass/secrets.yaml,
# referenced via "!secret key_name" in HA config. Not managed by Nix.
{
  config,
  lib,
  pkgs,
  backup,
  ...
}: let
  cfg = config.homelab.home-assistant;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  haDomain = "${cfg.subdomain}.${domain}";
in {
  options.homelab.home-assistant = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Home Assistant";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "Port for Home Assistant web interface";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "home";
      description = "Subdomain for Home Assistant";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Register IP for services dummy interface
      homelab.serviceIPs = [cfg.ip];
      networking.hosts.${cfg.ip} = [haDomain];

      # Firewall: allow HTTPS on VPN interface
      networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
        services.https.port
      ];

      # PostgreSQL database for Home Assistant recorder
      services.postgresql = {
        ensureDatabases = ["hass"];
        ensureUsers = [
          {
            name = "hass";
            ensureDBOwnership = true;
          }
        ];
      };

      services.home-assistant = {
        enable = true;
        # Minimal components: MQTT for zigbee2mqtt, prometheus for metrics
        extraComponents = [
          "mqtt"
          "prometheus"
        ];
        # psycopg2 required for PostgreSQL recorder backend
        extraPackages = ps: [ps.psycopg2];
        config = {
          homeassistant = {
            name = "Home";
            unit_system = "metric";
            time_zone = "Europe/Prague";
            # Trust nginx proxy
            external_url = "https://${haDomain}";
            internal_url = "http://127.0.0.1:${toString cfg.port}";
          };
          http = {
            server_host = "127.0.0.1";
            server_port = cfg.port;
            use_x_forwarded_for = true;
            trusted_proxies = ["127.0.0.1"];
          };
          # PostgreSQL recorder for long-term storage
          recorder = {
            db_url = "postgresql://@/hass";
            purge_keep_days = 30;
          };
          # Prometheus metrics endpoint without auth for internal scraping
          prometheus.requires_auth = false;
          # MQTT auto-discovery for zigbee2mqtt devices
          mqtt = {};
          # Required default integrations
          default_config = {};
        };
      };

      # Ensure home-assistant starts after dependencies
      systemd.services.home-assistant = {
        after = ["postgresql.service" "mosquitto.service" "zigbee2mqtt.service"];
        requires = ["postgresql.service"];
        wants = ["mosquitto.service" "zigbee2mqtt.service"];
      };

      # Nginx reverse proxy
      services.nginx.virtualHosts.${haDomain} = {
        listenAddresses = [cfg.ip];
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };

      # Prometheus scrape target for HA metrics
      homelab.scrapeTargets = [
        {
          job = "home-assistant";
          metricsPath = "/metrics/home-assistant";
        }
      ];

      # Metrics endpoint via nginx proxy
      services.nginx.virtualHosts."metrics".locations."/metrics/home-assistant".proxyPass = "http://127.0.0.1:${toString cfg.port}/api/prometheus";

      # Health check
      homelab.healthChecks = [
        {
          name = "Home Assistant";
          script = pkgs.writeShellApplication {
            name = "health-check-home-assistant";
            runtimeInputs = [pkgs.systemd];
            text = ''
              systemctl is-active --quiet home-assistant.service
            '';
          };
          timeout = 10;
        }
      ];

      # Alert
      homelab.alerts.home-assistant = [
        {
          alert = "HomeAssistantDown";
          expr = ''node_systemd_unit_state{name="home-assistant.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
          labels = {
            severity = "critical";
            host = config.homelab.host.hostName;
            type = "service";
          };
          annotations.summary = "Home Assistant is down";
        }
      ];
    }

    # Borg backup with database dump
    (backup.mkBorgBackup {
      name = "hass";
      hostName = config.homelab.host.hostName;
      paths = ["/var/lib/hass"];
      excludes = [
        # Exclude large cached data that can be regenerated
        "/var/lib/hass/.cache"
        "/var/lib/hass/tts"
      ];
      database = "hass";
      service = "home-assistant";
      hour = 3;
    })
  ]);
}

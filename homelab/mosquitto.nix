# Mosquitto MQTT broker for zigbee2mqtt communication
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.mosquitto;
in {
  options.homelab.mosquitto = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Mosquitto MQTT broker";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1883;
      description = "Port for MQTT broker";
    };
  };

  config = lib.mkIf cfg.enable {
    services.mosquitto = {
      enable = true;
      listeners = [
        {
          # Localhost only, no authentication needed for internal services
          address = "127.0.0.1";
          port = cfg.port;
          settings.allow_anonymous = true;
          acl = ["topic readwrite #"];
        }
      ];
    };

    # Health check
    homelab.healthChecks = [
      {
        name = "Mosquitto";
        script = pkgs.writeShellApplication {
          name = "health-check-mosquitto";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet mosquitto.service
          '';
        };
        timeout = 10;
      }
    ];

    # Alert
    homelab.alerts.mosquitto = [
      {
        alert = "MosquittoDown";
        expr = ''node_systemd_unit_state{name="mosquitto.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Mosquitto MQTT broker is down";
      }
    ];
  };
}

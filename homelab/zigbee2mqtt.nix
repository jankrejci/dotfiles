# Zigbee2mqtt bridge for Zigbee device management
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.zigbee2mqtt;
  mosquittoCfg = config.homelab.mosquitto;
in {
  options.homelab.zigbee2mqtt = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable zigbee2mqtt Zigbee bridge";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8099;
      description = "Port for zigbee2mqtt web interface";
    };
  };

  config = lib.mkIf cfg.enable {
    # Udev rules create /dev/zigbee symlink for ZBDongle-E.
    # The symlink provides stable device path regardless of USB port.
    # ZBDongle-E ships with either CP2102 or CH9102 USB-serial chip.
    # GROUP not needed because NixOS module adds zigbee2mqtt user to dialout group.
    services.udev.extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="zigbee", MODE="0660"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d4", SYMLINK+="zigbee", MODE="0660"
    '';

    services.zigbee2mqtt = {
      enable = true;
      settings = {
        # homeassistant integration enabled by default in NixOS module
        permit_join = false;
        serial.port = "/dev/zigbee";
        mqtt = {
          server = "mqtt://127.0.0.1:${toString mosquittoCfg.port}";
        };
        frontend = {
          port = cfg.port;
          host = "127.0.0.1";
        };
        advanced = {
          # Network key should be generated on first run and persisted
          network_key = "GENERATE";
          # Log level for debugging
          log_level = "info";
        };
      };
    };

    # Ensure zigbee2mqtt starts after mosquitto
    systemd.services.zigbee2mqtt = {
      after = ["mosquitto.service"];
      requires = ["mosquitto.service"];
    };

    # Health check
    homelab.healthChecks = [
      {
        name = "Zigbee2mqtt";
        script = pkgs.writeShellApplication {
          name = "health-check-zigbee2mqtt";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet zigbee2mqtt.service
          '';
        };
        timeout = 10;
      }
    ];

    # Alert
    homelab.alerts.zigbee2mqtt = [
      {
        alert = "Zigbee2mqttDown";
        expr = ''node_systemd_unit_state{name="zigbee2mqtt.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Zigbee2mqtt bridge is down";
      }
    ];
  };
}

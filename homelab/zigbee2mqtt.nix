# Zigbee2mqtt bridge for Zigbee device management
#
# Connects Nabu Casa ZBT-2 coordinator to Home Assistant via MQTT.
# Web frontend exposed through nginx on VPN interface for device management.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.zigbee2mqtt;
  mosquittoCfg = config.homelab.mosquitto;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  z2mDomain = "${cfg.subdomain}.${domain}";
in {
  options.homelab.zigbee2mqtt = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable zigbee2mqtt Zigbee bridge";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      description = "Port for zigbee2mqtt web interface";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "zigbee";
      description = "Subdomain for zigbee2mqtt web interface";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.mosquitto.enable;
        message = "homelab.zigbee2mqtt requires homelab.mosquitto.enable = true";
      }
      {
        assertion = config.homelab.sso-proxy.enable;
        message = "homelab.zigbee2mqtt requires homelab.sso-proxy.enable = true";
      }
    ];

    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [z2mDomain];

    # Firewall: allow HTTPS on VPN interface
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

    # Udev rule creates /dev/zigbee symlink for Nabu Casa ZBT-2.
    # The symlink provides stable device path regardless of USB port.
    # ZBT-2 uses Espressif ESP32 USB-serial chip, shows up as ttyACM0.
    services.udev.extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="831a", SYMLINK+="zigbee", GROUP="dialout", MODE="0660"
    '';

    services.zigbee2mqtt = {
      enable = true;
      settings = {
        # homeassistant integration enabled by default in NixOS module
        permit_join = false;
        serial = {
          port = "/dev/zigbee";
          # ZBT-2 uses Silicon Labs EFR32 with ember stack
          adapter = "ember";
          baudrate = 460800;
          rtscts = true;
        };
        mqtt = {
          server = "mqtt://127.0.0.1:${toString mosquittoCfg.port}";
        };
        frontend = {
          port = cfg.port;
          host = "127.0.0.1";
        };
        advanced = {
          # Network key generated on first run and persisted in state dir
          network_key = "GENERATE";
          log_level = "info";
        };
      };
    };

    # Ensure zigbee2mqtt starts after mosquitto
    systemd.services.zigbee2mqtt = {
      after = ["mosquitto.service"];
      requires = ["mosquitto.service"];
    };

    # Register as oauth2-proxy protected virtualHost
    services.oauth2-proxy.nginx.virtualHosts.${z2mDomain} = {};

    # Nginx reverse proxy for web frontend.
    # Uses explicit listen + onlySSL instead of forceSSL because the
    # oauth2-proxy nginx module adds auth_request to the vhost-level
    # extraConfig, which would break the HTTP redirect server block.
    services.nginx.virtualHosts.${z2mDomain} = {
      listen = [
        {
          addr = cfg.ip;
          port = services.https.port;
          ssl = true;
        }
      ];
      onlySSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    # Dashboard entry
    homelab.dashboardEntries = [
      {
        name = "Zigbee2MQTT";
        url = "https://${z2mDomain}";
        icon = ../assets/dashboard-icons/zigbee2mqtt.svg;
      }
    ];

    # Backup device pairings and network key
    homelab.backup.jobs = [
      {
        name = "zigbee2mqtt";
        paths = ["/var/lib/zigbee2mqtt"];
        excludes = ["/var/lib/zigbee2mqtt/log"];
        service = "zigbee2mqtt";
        hour = 4;
      }
    ];

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

# LoRaWAN gateway services for TTN using ChirpStack components
#
# Architecture:
# - chirpstack-concentratord: hardware abstraction for SX1301 concentrator
# - chirpstack-udp-forwarder: forwards packets to TTN via Semtech UDP protocol
#
# Gateway EUI-64 identifier is set declaratively per host.
# Derive it from the MAC address: read /sys/class/net/<iface>/address,
# remove colons, uppercase, insert FFFE after first 6 hex chars.
# Example: b8:27:eb:c5:ec:e3 -> B827EBFFFEC5ECE3
#
# GNSS Architecture for RAK2245:
#
# The RAK2245 uses a u-blox MAX-7Q GPS module connected via UART to the RPi.
# PPS signal is internally routed from u-blox to SX1301 on the HAT PCB, not
# exposed to RPi GPIO. This enables precise timing for Class B beaconing.
#
# GPS time sync requires:
# 1. UBX NAV-TIMEGPS messages from u-blox, not just NMEA
# 2. PPS signal captured by SX1301 internal counter
# 3. Correlation between GPS time and PPS timestamp in the HAL
#
# The gpsd approach is used because:
# 1. gpsd detects u-blox and switches it to UBX+NMEA protocol automatically
# 2. gpsd sends UBX CFG commands to enable NAV-TIMEGPS output
# 3. concentratord reads GPS data from gpsd and correlates with PPS
#
# Without gpsd sending UBX commands, the u-blox outputs NMEA only, and gpsd
# reports driver "NMEA0183" instead of "u-blox". The concentratord then fails
# with "No u-blox GNSS device found" because it requires UBX protocol.
#
# Hardware dependency: GPIO14 must work for UART TX to send UBX commands.
# Some RPi boards have dead GPIO14. Tested: RPi 3B works, RPi 3B+ failed.
# Symptom: gpsd shows "driver":"NMEA0183" instead of "driver":"u-blox".
#
# GPS sync behavior on startup:
# - First 2-3 NAV-TIMEGPS messages show "lgw_gps_sync failed" while calibrating
# - After ~2 seconds, sync succeeds and warnings stop
# - "GPS time reference is not valid" with 56-year age means sync never worked
#
# Debugging commands:
#   Check GPS protocol: ssh rak2245 'sudo journalctl -u chirpstack-concentratord -n 50 | grep -iE "u-blox|NMEA|driver"'
#   Check GPS sync: ssh rak2245 'sudo journalctl -u chirpstack-concentratord -n 50 | grep -iE "sync|time.*valid"'
#   Raw GPS data: ssh rak2245 'sudo timeout 3 cat /dev/ttyAMA0 | xxd | head -20'
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.lorawan-gateway;
  tomlFormat = pkgs.formats.toml {};
  # UDP forwarder configuration
  udpForwarderConfig = tomlFormat.generate "udp-forwarder.toml" {
    udp_forwarder = {
      log_level = "INFO";
      log_to_syslog = false;
      servers = [
        {
          server = "${cfg.server}:${toString cfg.port}";
          keepalive_interval_secs = 10;
          keepalive_max_failures = 3;
          forward_crc_ok = true;
          forward_crc_invalid = false;
          forward_crc_missing = false;
        }
      ];
    };
    concentratord = {
      event_url = "ipc:///tmp/concentratord_event";
      command_url = "ipc:///tmp/concentratord_command";
    };
  };

  # EU868 channel frequencies for 8-channel gateway
  eu868Channels = [
    868100000
    868300000
    868500000
    867100000
    867300000
    867500000
    867700000
    867900000
  ];

  concentratordConfig = tomlFormat.generate "concentratord.toml" {
    concentratord = {
      log_level = "INFO";
      log_to_syslog = false;
      stats_interval = "30s";
      api = {
        event_bind = "ipc:///tmp/concentratord_event";
        command_bind = "ipc:///tmp/concentratord_command";
      };
    };
    gateway =
      {
        antenna_gain = 2;
        lorawan_public = true;
        model = cfg.model;
        region = cfg.region;
        gateway_id = cfg.eui;
        time_fallback_enabled = true;
        concentrator = {
          multi_sf_channels = eu868Channels;
          lora_std = {
            frequency = 868300000;
            bandwidth = 250000;
            spreading_factor = 7;
          };
          fsk = {
            frequency = 868800000;
            bandwidth = 125000;
            datarate = 50000;
          };
        };
      }
      // lib.optionalAttrs cfg.gnss.enable {
        model_flags = ["GNSS"];
        gnss_dev_path = "gpsd://localhost:2947";
      };
  };

  # Script to reset SX1301 via GPIO17
  # libgpiod v2 syntax: -t toggles after period, trailing 0 exits immediately
  resetScript = pkgs.writeShellApplication {
    name = "sx1301-reset";
    runtimeInputs = [pkgs.libgpiod];
    text = ''
      gpioset -c gpiochip0 -t 100ms,0 17=0
      sleep 0.1
    '';
  };
in {
  options.homelab.lorawan-gateway = {
    enable = lib.mkEnableOption "LoRaWAN gateway services";

    eui = lib.mkOption {
      type = lib.types.strMatching "[0-9A-Fa-f]{16}";
      description = "Gateway EUI-64 identifier, 16 hex characters";
      example = "B827EBFFFEC5ECE3";
    };

    model = lib.mkOption {
      type = lib.types.enum ["rak_2245" "rak_2287" "rak_2247"];
      default = "rak_2245";
      description = "Concentrator model for chirpstack-concentratord";
    };

    region = lib.mkOption {
      type = lib.types.enum ["EU868" "US915" "AU915" "AS923" "CN470" "IN865" "KR920"];
      default = "EU868";
      description = "LoRaWAN frequency plan";
    };

    server = lib.mkOption {
      type = lib.types.str;
      default = "eu1.cloud.thethings.network";
      description = "Network server address for UDP packet forwarding";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1700;
      description = "Network server UDP port";
    };

    gnss = {
      enable = lib.mkEnableOption "GNSS/GPS support for precise timing and location";

      device = lib.mkOption {
        type = lib.types.str;
        default = "/dev/ttyAMA0";
        description = "Serial device path for GNSS module";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.gpsd = lib.mkIf cfg.gnss.enable {
      enable = true;
      devices = [cfg.gnss.device];
      nowait = true;
      readonly = false;
      extraArgs = ["-s" "9600"];
    };

    # SX1301 reset service - runs once before concentratord
    systemd.services.sx1301-reset = {
      description = "Reset SX1301 concentrator via GPIO";
      wantedBy = ["multi-user.target"];
      before = ["chirpstack-concentratord.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe resetScript;
      };
    };

    # ChirpStack Concentratord - hardware abstraction for SX1301
    systemd.services.chirpstack-concentratord = {
      description = "ChirpStack Concentratord";
      wantedBy = ["multi-user.target"];
      after =
        ["sx1301-reset.service"]
        ++ lib.optionals cfg.gnss.enable ["gpsd.service"];
      requires = ["sx1301-reset.service"];
      serviceConfig = {
        ExecStart = "${pkgs.chirpstack-concentratord}/bin/chirpstack-concentratord-sx1301 -c ${concentratordConfig}";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "root";
        Group = "root";
      };
    };

    # ChirpStack UDP Forwarder - sends packets to TTN
    systemd.services.chirpstack-udp-forwarder = {
      description = "ChirpStack UDP Forwarder";
      wantedBy = ["multi-user.target"];
      after = ["chirpstack-concentratord.service" "network-online.target"];
      requires = ["chirpstack-concentratord.service"];
      wants = ["network-online.target"];
      serviceConfig = {
        ExecStart = "${pkgs.chirpstack-udp-forwarder}/bin/chirpstack-udp-forwarder -c ${udpForwarderConfig}";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "root";
        Group = "root";
      };
    };

    # Required packages for GPIO control
    environment.systemPackages = [pkgs.libgpiod];
  };
}

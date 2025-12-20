# LoRaWAN gateway services for TTN using ChirpStack components
#
# Architecture:
# - chirpstack-concentratord: hardware abstraction for SX1301 concentrator
# - chirpstack-udp-forwarder: forwards packets to TTN via Semtech UDP protocol
#
# Gateway ID is derived from MAC address at runtime using EUI-64 conversion.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.lorawan-gateway;

  # Configuration for chirpstack-udp-forwarder (static, doesn't need gateway ID)
  udpForwarderConfig = pkgs.writeText "udp-forwarder.toml" ''
    [udp_forwarder]
    log_level = "INFO"
    log_to_syslog = false

    [[udp_forwarder.servers]]
    server = "${cfg.server}:${toString cfg.port}"
    keepalive_interval_secs = 10
    keepalive_max_failures = 3
    forward_crc_ok = true
    forward_crc_invalid = false
    forward_crc_missing = false

    [concentratord]
    event_url = "ipc:///tmp/concentratord_event"
    command_url = "ipc:///tmp/concentratord_command"
  '';

  # Script to reset SX1301 via GPIO17
  resetScript = pkgs.writeShellScript "sx1301-reset" ''
    set -euo pipefail
    # SX1301 reset: pull GPIO17 low for 100ms, then release
    ${pkgs.libgpiod}/bin/gpioset --mode=time --usec=100000 gpiochip0 17=0
    ${pkgs.libgpiod}/bin/gpioset gpiochip0 17=1
    sleep 0.1
  '';

  # Script to generate concentratord config with gateway ID from MAC
  generateConcentratordConfigScript = pkgs.writeShellScript "generate-concentratord-config" ''
    set -euo pipefail
    mkdir -p /run/lorawan-gateway

    # Get MAC address from first available interface
    MAC=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/wlan0/address)

    # Convert MAC to EUI-64 by inserting FFFE in middle
    # Example: b8:27:eb:12:34:56 -> B827EBFFFE123456
    EUI=$(echo "$MAC" | tr -d ':' | tr '[:lower:]' '[:upper:]' | sed 's/\(......\)/\1FFFE/')

    echo "Generated gateway ID: $EUI"

    cat > /run/lorawan-gateway/concentratord.toml <<EOF
    [concentratord]
    log_level = "INFO"
    log_to_syslog = false
    stats_interval = "30s"

    [concentratord.api]
    event_bind = "ipc:///tmp/concentratord_event"
    command_bind = "ipc:///tmp/concentratord_command"

    [gateway]
    antenna_gain = 0
    lorawan_public = true
    model = "${cfg.model}"
    region = "${cfg.region}"
    gateway_id = "$EUI"
    EOF
  '';
in {
  options.homelab.lorawan-gateway = {
    enable = lib.mkEnableOption "LoRaWAN gateway services";

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
  };

  config = lib.mkIf cfg.enable {
    # SX1301 reset service - runs once before concentratord
    systemd.services.sx1301-reset = {
      description = "Reset SX1301 concentrator via GPIO";
      wantedBy = ["multi-user.target"];
      before = ["chirpstack-concentratord.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = resetScript;
      };
    };

    # Generate concentratord config with gateway ID from MAC address
    systemd.services.lorawan-gateway-config = {
      description = "Generate LoRaWAN gateway configuration";
      wantedBy = ["multi-user.target"];
      before = ["chirpstack-concentratord.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = generateConcentratordConfigScript;
      };
    };

    # ChirpStack Concentratord - hardware abstraction for SX1301
    systemd.services.chirpstack-concentratord = {
      description = "ChirpStack Concentratord";
      wantedBy = ["multi-user.target"];
      after = ["sx1301-reset.service" "lorawan-gateway-config.service"];
      requires = ["sx1301-reset.service" "lorawan-gateway-config.service"];
      serviceConfig = {
        ExecStart = "${pkgs.chirpstack-concentratord}/bin/chirpstack-concentratord-sx1301 -c /run/lorawan-gateway/concentratord.toml";
        Restart = "on-failure";
        RestartSec = "5s";
        # Run as root for SPI access
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

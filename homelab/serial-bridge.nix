# Serial port bridged to the VPN
#
# - ser2net exposes a local serial device as raw TCP on localhost
# - nginx stream proxy publishes it to the VPN subnet only
# - lets a service on another host drive the device, e.g. the printer
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.serial-bridge;
  services = config.homelab.services;

  # A new client replaces a stale one, so a bridge that reconnects after a
  # half-open link is not locked out until the old session times out. UUCP
  # locks need write access to /run/lock, which the unprivileged unit lacks,
  # and nothing else on the host opens the port.
  ser2netConfig = pkgs.writeText "ser2net.yaml" ''
    connection: &bridge
      accepter: tcp,127.0.0.1,${toString cfg.port.ser2net}
      connector: serialdev(uucplock=false),${cfg.device},${toString cfg.baud}n81,local
      options:
        kickolduser: true
  '';
in {
  options.homelab.serial-bridge = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Bridge a serial device to the VPN over TCP";
    };

    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/ttyAMA0";
      description = "Serial device to bridge";
    };

    baud = lib.mkOption {
      type = lib.types.int;
      default = 115200;
      description = "Serial baud rate";
    };

    port = {
      ser2net = lib.mkOption {
        type = lib.types.port;
        default = 2000;
        description = "Port ser2net listens on at localhost";
      };

      proxy = lib.mkOption {
        type = lib.types.port;
        default = 2001;
        description = "Port serving the serial device to the VPN";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.ser2net = {
      description = "Serial to TCP bridge for ${cfg.device}";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        # The debug flag keeps ser2net in the foreground and logs to stderr,
        # which lands in the journal.
        ExecStart = "${lib.getExe pkgs.ser2net} -n -d -c ${ser2netConfig}";
        Restart = "always";
        RestartSec = "5s";
        DynamicUser = true;
        SupplementaryGroups = ["dialout"];
        DevicePolicy = "closed";
        DeviceAllow = ["${cfg.device} rw"];
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      };
    };

    services.nginx = {
      enable = true;
      streamConfig = ''
        server {
          listen 0.0.0.0:${toString cfg.port.proxy};
          allow ${services.netbird.subnet};
          deny all;
          proxy_pass 127.0.0.1:${toString cfg.port.ser2net};
        }
      '';
    };

    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [cfg.port.proxy];

    homelab.healthChecks = [
      {
        name = "ser2net";
        script = pkgs.writeShellApplication {
          name = "health-check-ser2net";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet ser2net.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

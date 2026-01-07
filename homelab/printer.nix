# IPP print server and eSCL scanner for Brother DCP-T730DW
#
# Architecture:
#   USB device → ipp-usb on localhost:60000 → nginx proxy → HTTPS on VPN IP:443
#
# ipp-usb exposes the USB device with IPP Everywhere and eSCL protocols.
# nginx provides TLS termination and proxies requests to ipp-usb.
# Host header preservation ensures ipp-usb returns correct URIs in responses.
#
# Why nginx instead of CUPS:
#   Simpler architecture. ipp-usb already speaks IPP Everywhere which clients
#   understand natively. No need for CUPS queue management on the server.
#
# Why Host header matters:
#   ipp-usb embeds the server URI in IPP responses as "printer-uri-supported".
#   Without proper Host header, it returns localhost URIs. With Host header
#   preservation, it returns the external hostname clients can reach.
#
# Client configuration:
#   Printer: ipps://brother.krejci.io/ipp/print
#   Scanner: https://brother.krejci.io/eSCL
#
# Debugging commands:
#   curl -k https://brother.krejci.io/eSCL/ScannerCapabilities
#   ipptool -tv ipps://brother.krejci.io/ipp/print get-printer-attributes.test
{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.printer;
  global = config.homelab.global;
  services = config.homelab.services;
  printerDomain = "${cfg.subdomain}.${global.domain}";
in {
  options.homelab.printer = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable print server";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "VPN IP address for nginx to listen on";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "brother";
      description = "Subdomain for printer";
    };
  };

  config = lib.mkIf cfg.enable {
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [printerDomain];

    # Allow HTTPS on VPN interface only
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

    # ipp-usb exposes USB device on localhost with IPP Everywhere and eSCL
    services.ipp-usb.enable = true;
    boot.blacklistedKernelModules = ["usblp"];
    environment.etc."ipp-usb/ipp-usb.conf".text = ''
      [network]
      interface = loopback
      ipv6 = disable
      http-min-port = 60000
      http-max-port = 60010
      dns-sd = disable
    '';

    # nginx proxies to ipp-usb with TLS termination
    # Host header preservation ensures ipp-usb returns correct URIs
    services.nginx = {
      enable = true;
      virtualHosts.${printerDomain} = {
        listenAddresses = [cfg.ip];
        forceSSL = true;
        useACMEHost = global.domain;
        locations."/" = {
          proxyPass = "http://localhost:60000";
          extraConfig = ''
            proxy_set_header Host localhost:60000;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_http_version 1.1;
            proxy_buffering off;
          '';
        };
      };
    };

    # Wait for services interface before nginx binds
    systemd.services.nginx.after = ["sys-subsystem-net-devices-services.device"];
  };
}

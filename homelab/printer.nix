# IPP print server and eSCL scanner for Brother DCP-T730DW
#
# Architecture:
#   USB device → ipp-usb on localhost:60000 → nginx proxy → HTTPS on VPN IP:443
#
# ipp-usb exposes the USB device with IPP Everywhere and eSCL protocols.
# nginx provides TLS termination and proxies requests to ipp-usb.
#
# Client configuration:
#   Printer: ipps://brother.krejci.io/ipp/print
#   Scanner: https://brother.krejci.io/eSCL
#   Desktop needs: hardware.sane.extraBackends = [pkgs.sane-airscan];
#
# Debugging:
#   curl -k https://brother.krejci.io/eSCL/ScannerCapabilities
#   ipptool -tv ipps://brother.krejci.io/ipp/print get-printer-attributes.test
#
# ---
# Design decisions and alternatives considered:
#
# Why ipp-usb instead of CUPS:
#   CUPS cannot be proxied through nginx for two reasons:
#   1. CVE-2009-0164 security fix makes CUPS reject requests to localhost
#      that arrive with external Host headers. nginx would need to proxy to
#      CUPS on localhost but forward the external Host header for correct URIs.
#   2. Even when CUPS listens on VPN IP directly, it returns printer-uri based
#      on connection source, ignoring the ServerName directive. Clients store
#      these URIs and fail on subsequent requests.
#   ipp-usb respects the Host header and returns correct URIs in responses.
#
# Why nginx proxy instead of ipp-usb on port 631 directly:
#   Android Default Print Service ignores custom ports and always connects to
#   631. When ipp-usb listened on port 60000 directly on VPN IP, Android could
#   not discover it. We need nginx on 443 with proper Host header forwarding.
#
# Why Host header preservation is critical:
#   ipp-usb embeds "printer-uri-supported" in IPP responses. Without proper
#   Host header, it returns localhost:60000 URIs. With Host header set to the
#   external hostname, clients receive URIs they can actually reach.
#
# Why not nginx path rewriting to support both CUPS and ipp-usb:
#   IPP protocol embeds printer-uri in the request BODY, not just the HTTP
#   path. tcpdump shows: `printer-uri = ipp://host/ipp/printer` inside the
#   POST body. CUPS reads this URI to lookup the printer queue. HTTP-level
#   path rewriting cannot fix the mismatch between IPP Everywhere paths
#   like /ipp/print and CUPS paths like /printers/Name.
#
# Why cups-browsed is disabled on desktop clients:
#   cups-browsed discovers _printer._tcp mDNS records from ipp-usb and creates
#   broken "Unknown" printer queues. It also had CVEs disclosed in late 2024.
#   With cups-browsed disabled, CUPS 2.2.4+ discovers _ipp._tcp directly.
#
# Known limitation - Android availability:
#   Android shows "unavailable" after first successful print. This happens
#   because Android uses mDNS to refresh printer availability status, but
#   Netbird VPN is Layer 3 and does not support multicast. Without mDNS
#   broadcasts, Android caches stale state. Workaround: forget and re-add
#   the printer, or use Mopria Print Service which handles this better.
{
  config,
  lib,
  pkgs,
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

    # nginx proxies to ipp-usb with TLS termination.
    # Host header is set to localhost:60000 so ipp-usb accepts the connection.
    # This means printer-uri-supported in responses contains localhost URIs,
    # which breaks Android status refresh. See "Known limitation" above.
    # Using $host would fix URIs but Android still fails due to missing mDNS.
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

    # Alert when ipp-usb service goes down
    homelab.alerts.printer = [
      {
        alert = "IppUsbDown";
        expr = ''node_systemd_unit_state{name="ipp-usb.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "IPP-USB print server is not active";
      }
    ];

    homelab.healthChecks = [
      {
        name = "IPP-USB";
        script = pkgs.writeShellApplication {
          name = "health-check-ipp-usb";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet ipp-usb.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

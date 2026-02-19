# Netbird public proxy and signal server
#
# Public-facing entry point (vpsfree) for Netbird client connectivity.
# Management and relay run on thinkcenter; this host proxies them via WG tunnel.
# Signal runs locally to avoid pprof port 6060 conflict with management.
# TODO: migrate to combined netbird-server binary (v0.65.0+) on thinkcenter.
#
# - nginx http: management API and signal gRPC on port 443
# - nginx stream: relay TLS passthrough on port 33080, STUN UDP on port 3478
# - signal: local gRPC service for peer connection handshakes
#
# Clients use api.krejci.io as their management URL. Signal and relay URLs
# are distributed automatically by the management server.
#
# vpsfree is LXC-based with a shared kernel, so no sensitive state here.
# All secrets and databases live on thinkcenter. vpsfree only forwards
# traffic via the WG backup tunnel.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.netbird-gateway;
  global = config.homelab.global;
  services = config.homelab.services;
  allHosts = config.homelab.hosts;
  domain = global.domain;
  apiDomain = "api.${domain}";

  # Management server is on a different host, reached via WG backup tunnel
  managementWgIp = allHosts.${cfg.managementHost}.homelab.tunnel.ip;
in {
  options.homelab.netbird-gateway = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Netbird public proxy";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "Service IP for nginx to listen on";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      description = "Public network interface for firewall rules";
    };

    managementHost = lib.mkOption {
      type = lib.types.str;
      description = "Hostname of the management server reached via WG tunnel";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register IP for services dummy interface and enable shared nginx module
    homelab.serviceIPs = [cfg.ip];
    homelab.nginx.enable = true;
    homelab.nginx.publicDomains = [apiDomain];

    # Signal server runs locally to avoid pprof conflict with management.
    # Stateless broker that coordinates direct WireGuard tunnel setup between peers.
    services.netbird.server.signal = {
      enable = true;
      package = pkgs.unstable.netbird-signal;
      domain = apiDomain;
      port = services.netbird.port.signal;
      logLevel = "INFO";
    };

    # Nginx: public entry point proxying Netbird traffic.
    # Management and relay are forwarded to thinkcenter over WG tunnel.
    # Signal is served locally.
    services.nginx = {
      virtualHosts.${apiDomain} = {
        listenAddresses = [cfg.ip];
        forceSSL = true;
        useACMEHost = domain;

        # Management REST API proxied to thinkcenter over WG tunnel
        locations."/api" = {
          proxyPass = "https://${managementWgIp}";
          recommendedProxySettings = true;
        };

        # Management gRPC proxied to thinkcenter over WG tunnel.
        # NixOS proxyPass only generates proxy_pass which does not support
        # gRPC schemes. Use grpc_pass directive directly via extraConfig.
        locations."/management.ManagementService/" = {
          extraConfig = ''
            grpc_pass grpcs://${managementWgIp};
            grpc_read_timeout 1d;
            grpc_send_timeout 1d;
            grpc_socket_keepalive on;
          '';
        };

        # Signal gRPC served by local signal instance
        locations."/signalexchange.SignalExchange/" = {
          extraConfig = ''
            grpc_pass grpc://localhost:${toString services.netbird.port.signal};
            grpc_read_timeout 1d;
            grpc_send_timeout 1d;
            grpc_socket_keepalive on;
          '';
        };
      };

      # Relay TLS and STUN UDP passthrough to thinkcenter via WG tunnel
      streamConfig = ''
        server {
            listen ${toString services.netbird.port.relay};
            proxy_pass ${managementWgIp}:${toString services.netbird.port.relay};
        }
        server {
            listen 3478 udp;
            proxy_pass ${managementWgIp}:3478;
        }
      '';
    };

    # HTTPS for API/signal, relay TCP passthrough, STUN UDP passthrough
    networking.firewall.interfaces.${cfg.interface} = {
      allowedTCPPorts = [443 services.netbird.port.relay];
      allowedUDPPorts = [3478];
    };
  };
}

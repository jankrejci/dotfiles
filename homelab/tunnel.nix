# Encrypted tunnel between thinkcenter and vpsfree
#
# Provides encrypted transport for borg backups and the TLS proxy.
# The proxy (when enabled) runs as a separate nginx process doing L4
# SNI-based routing. It forwards listed domains to the backend peer
# while blackholing unknown domains. The main nginx instance is unaffected
# since the proxy binds 0.0.0.0:443 and Linux dispatches to the more-specific
# service IP bindings first.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.tunnel;
  services = config.homelab.services;
  host = config.homelab.host;
  global = config.homelab.global;
  allHosts = config.homelab.hosts;

  privateKeyFile = "/var/lib/wireguard/wg-${host.hostName}-private";

  mkPeer = peerName: let
    peerHost = allHosts.${peerName};
    peerCfg = peerHost.homelab.tunnel;
    peerPublicKey = lib.fileContents ../wireguard-keys/${peerName}-public;
  in
    {
      PublicKey = peerPublicKey;
      AllowedIPs = ["${peerCfg.ip}/32"];
      PersistentKeepalive = 25;
    }
    // lib.optionalAttrs (peerCfg.server or false) {
      Endpoint = "wg.${global.domain}:${toString cfg.port}";
    };
in {
  options.homelab.tunnel = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable encrypted tunnel";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address on the tunnel";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 51821;
      description = "Port for WireGuard transport";
    };

    server = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Act as server with public endpoint";
    };

    peers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of peer hostnames";
    };

    proxy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable TLS proxy for public service exposure";
      };

      domains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Domain names to forward to the backend peer";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedUDPPorts = [cfg.port];

    systemd.network.netdevs."50-wg0" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg0";
        # VPS containers often have constrained outer MTU, 1280 works everywhere
        MTUBytes = "1280";
      };
      wireguardConfig = {
        PrivateKeyFile = privateKeyFile;
        ListenPort = cfg.port;
      };
      wireguardPeers = map mkPeer cfg.peers;
    };

    systemd.network.networks."50-wg0" = {
      matchConfig.Name = "wg0";
      address = ["${cfg.ip}/24"];
      networkConfig.DHCP = "no";
    };

    # Prometheus exporter for WireGuard metrics
    services.prometheus.exporters.wireguard = {
      enable = true;
      port = 9586;
      listenAddress = "127.0.0.1";
      openFirewall = false;
    };

    # WireGuard metrics via common metrics vhost
    services.nginx.virtualHosts."metrics".locations."/metrics/wireguard" = {
      proxyPass = "http://127.0.0.1:9586/metrics";
    };

    # Scrape target for prometheus
    homelab.scrapeTargets = [
      {
        job = "wireguard";
        metricsPath = "/metrics/wireguard";
      }
    ];

    # Alert rules for tunnel connectivity
    homelab.alerts.wireguard = [
      {
        alert = "WireGuardTunnelDown";
        expr = ''wireguard_latest_handshake_delay_seconds{interface="wg0"} > 180'';
        labels = {
          severity = "critical";
          host = host.hostName;
          type = "service";
        };
        annotations.summary = "WireGuard tunnel has no recent handshake";
      }
    ];

    # Health check for tunnel interface and peer connectivity
    homelab.healthChecks = [
      {
        name = "Wireguard";
        script = pkgs.writeShellApplication {
          name = "health-check-wireguard";
          runtimeInputs = [pkgs.iproute2 pkgs.wireguard-tools pkgs.gawk pkgs.coreutils pkgs.iputils];
          text = ''
            # Check interface is up
            ip link show wg0 > /dev/null 2>&1 || {
              echo "Interface down"
              exit 1
            }

            # Check handshake is recent
            handshake=$(wg show wg0 latest-handshakes | awk '{print $2}')
            if [ -n "$handshake" ] && [ "$handshake" != "0" ]; then
              current_time=$(date +%s)
              age=$((current_time - handshake))
              if [ "$age" -gt 180 ]; then
                echo "Stale handshake ($age seconds)"
                exit 1
              fi
            fi

            # Ping all peers
            ${lib.concatMapStringsSep "\n" (peerName: ''
                ping -c 1 -W 2 ${allHosts.${peerName}.homelab.tunnel.ip} > /dev/null 2>&1 || {
                  echo "Cannot reach ${peerName}"
                  exit 1
                }
              '')
              cfg.peers}
          '';
        };
        timeout = 15;
      }
    ];

    # TLS proxy: separate nginx process for L4 SNI-based routing.
    # Runs independently from the main nginx so a proxy failure cannot take
    # down local services like watchdog. Uses 0.0.0.0:443 which coexists with
    # main nginx on specific service IPs thanks to Linux socket dispatch.
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.proxy.enable [443];

    systemd.services.tunnel-proxy = lib.mkIf cfg.proxy.enable (let
      peerName = builtins.head cfg.peers;
      backend = allHosts.${peerName}.homelab.tunnel.ip;

      sniMap =
        lib.concatMapStringsSep "\n"
        (d: "            ${d} backend;")
        cfg.proxy.domains;

      proxyConfig = pkgs.writeText "tunnel-proxy.conf" ''
        error_log syslog:server=unix:/dev/log;
        pid /run/tunnel-proxy/tunnel-proxy.pid;

        events {
            worker_connections 512;
        }

        stream {
            map $ssl_preread_server_name $tunnel_backend {
        ${sniMap}
                default blackhole;
            }

            upstream backend {
                server ${backend}:443;
            }

            # Unknown domains get connection refused
            upstream blackhole {
                server 127.0.0.1:1;
            }

            server {
                listen 0.0.0.0:443;
                ssl_preread on;
                proxy_pass $tunnel_backend;
                proxy_connect_timeout 5s;
            }
        }
      '';
    in {
      description = "TLS tunnel proxy for public service exposure";
      after = ["network-online.target" "sys-subsystem-net-devices-wg0.device"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        ExecStartPre = "${pkgs.nginx}/bin/nginx -t -c ${proxyConfig} -e /run/tunnel-proxy/error.log -q";
        ExecStart = "${pkgs.nginx}/bin/nginx -c ${proxyConfig} -e /run/tunnel-proxy/error.log -g 'daemon off;'";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RuntimeDirectory = "tunnel-proxy";
        DynamicUser = true;
        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
      };
    });

    assertions = lib.optionals cfg.proxy.enable [
      {
        assertion = cfg.peers != [];
        message = "tunnel.proxy requires at least one peer as backend";
      }
      {
        assertion = cfg.proxy.domains != [];
        message = "tunnel.proxy.domains must not be empty";
      }
    ];
  };
}

# WireGuard backup tunnel between thinkcenter and vpsfree
{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.wireguard;
  services = config.homelab.services;
  host = config.homelab.host;
  global = config.homelab.global;
  allHosts = config.homelab.hosts;

  privateKeyFile = "/var/lib/wireguard/wg-${host.hostName}-private";

  mkPeer = peerName: let
    peerHost = allHosts.${peerName};
    peerCfg = peerHost.homelab.wireguard;
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
  options.homelab.wireguard = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable WireGuard backup tunnel";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address on the WireGuard tunnel";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 51821;
      description = "Port for WireGuard";
    };

    server = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Act as WireGuard server with public endpoint";
    };

    peers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of peer hostnames";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedUDPPorts = [cfg.port];

    systemd.network.netdevs."50-wg0" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg0";
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

    # Alert rules for wireguard tunnel
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
  };
}

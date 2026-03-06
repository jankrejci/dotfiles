# Network configuration with systemd-networkd
#
# - DHCP for ethernet and WiFi
# - dummy interface for service IPs
# - unbound recursive DNS resolver with DNSSEC
# - systemd-resolved as stub forwarding to unbound
# - prometheus node exporter with metrics proxy
#
# Known limitation: captive portals break recursive resolution.
# Workaround: systemctl stop unbound
{
  config,
  lib,
  ...
}: let
  services = config.homelab.services;
  host = config.homelab.host;

  # Service IPs registered by homelab modules via homelab.serviceIPs
  serviceIPs = config.homelab.serviceIPs;
  hasServices = serviceIPs != [];
  metricsDir = "/var/lib/prometheus-node-exporter";
  unboundPort = config.homelab.unbound.port;
in {
  options.homelab.unbound.port = lib.mkOption {
    type = lib.types.port;
    default = 5335;
    description = "Port for local unbound recursive DNS resolver";
  };

  config = {
    # Avoid collision of the dhcp with the systemd.network
    networking = {
      useDHCP = lib.mkForce false;
      useNetworkd = lib.mkForce true;
    };

    # Do not wait to long for interfaces to become online,
    # this is especially handy for notebooks on wifi,
    # where the eth interface is disconnected
    boot.initrd.systemd.network.wait-online.enable = false;

    networking = {
      hostName = host.hostName;
      firewall.enable = true;
      # Use nftables instead of iptables (modern, better performance)
      nftables.enable = true;
    };

    # Recursive DNS resolver, eliminates dependency on upstream forwarders.
    # After cache warmup, most lookups resolve in a single hop to an authoritative server.
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = ["127.0.0.1"];
          port = unboundPort;
          access-control = ["127.0.0.0/8 allow"];
          do-ip6 = false;

          # DNSSEC validation, unbound's implementation is mature unlike resolved's
          auto-trust-anchor-file = "/var/lib/unbound/root.key";
          val-clean-additional = true;

          # Privacy: minimise query names sent to authoritative servers per RFC 7816
          qname-minimisation = true;

          # Prefetch entries before TTL expiry to keep popular records warm
          prefetch = true;

          # Serve expired cache entries while fetching fresh data in background
          serve-expired = true;
          serve-expired-ttl = 86400;

          # Harden against abuse
          harden-glue = true;
          harden-dnssec-stripped = true;
          use-caps-for-id = true;

          verbosity = 0;
          log-queries = false;

          num-threads = 2;
          msg-cache-slabs = 2;
          rrset-cache-slabs = 2;
          infra-cache-slabs = 2;
          key-cache-slabs = 2;
        };
      };
    };

    # Resolved as stub resolver forwarding to unbound.
    # Netbird split DNS is unaffected since it uses D-Bus SetLinkDNS on the
    # nb0 interface, which is orthogonal to the global DNS upstream.
    services.resolved = {
      enable = true;
      extraConfig = ''
        [Resolve]
        DNS=127.0.0.1:${toString unboundPort}
        # No fallback: all DNS must go through unbound for DNSSEC validation
        FallbackDNS=
        DNSSEC=no
        DNSStubListener=yes
        MulticastDNS=no
        LLMNR=no
        Cache=yes
      '';
    };

    # Ensure unbound is running before resolved starts
    systemd.services.systemd-resolved = {
      after = ["unbound.service"];
      wants = ["unbound.service"];
    };

    # Configure systemd-networkd
    systemd.network = {
      enable = true;

      wait-online = {
        anyInterface = true;
        timeout = 10;
      };

      # Dummy interface for service IPs (Netbird routes these subnets to the host)
      netdevs."30-services" = lib.mkIf hasServices {
        netdevConfig = {
          Kind = "dummy";
          Name = "services";
        };
      };

      networks = {
        # Service IPs on dummy interface
        "30-services" = lib.mkIf hasServices {
          matchConfig.Name = "services";
          address = map (ip: "${ip}/24") serviceIPs;
          networkConfig.DHCP = "no";
        };

        # Enable dhcp via systemd-network
        # This can be overriden for servers with fixed ip
        "98-all-ethernet" = lib.mkDefault {
          matchConfig.Type = "ether";
          DHCP = "yes";
          # Prefer ethernet over WiFi for default route
          dhcpV4Config.RouteMetric = 100;
          dhcpV6Config.RouteMetric = 100;
        };
        "99-all-wifi" = {
          matchConfig.Type = "wlan";
          DHCP = "yes";
          # Lower priority than ethernet
          dhcpV4Config.RouteMetric = 600;
          dhcpV6Config.RouteMetric = 600;
        };
      };
    };

    # NetworkManager disabled by default for headless systems, enabled in desktop.nix
    networking.networkmanager = {
      enable = lib.mkDefault false;
      # Don't let NetworkManager manage systemd-networkd interfaces
      # Include nb-* pattern to cover both homelab and any manually configured networks
      unmanaged = ["nb-*"];
      # Enhanced DNS handling
      dns = "systemd-resolved";
      # Use iwd instead of wpa_supplicant for faster Wi-Fi connection/reconnection
      wifi.backend = "iwd";
      # Connection timeout and retry settings
      settings = {
        main = {
          # Faster connection establishment
          dhcp = "dhclient";
        };
      };
    };

    # iwd for wifi, used by both NetworkManager and standalone systemd-networkd
    networking.wireless.iwd = {
      enable = true;
      settings = {
        General = {
          # Less aggressive roaming to avoid ping-pong between UniFi APs.
          # Defaults are -70 and -76 which trigger roaming too early in
          # dense AP environments, causing repeated disconnects.
          RoamThreshold = -75;
          RoamThreshold5G = -80;
          # Wait longer before retrying a roam attempt, default is 60 seconds
          RoamRetryInterval = 120;
        };
        Network = {
          EnableIPv6 = true;
        };
        Settings = {
          AutoConnect = true;
        };
      };
    };

    services.prometheus.exporters.node = {
      enable = true;
      openFirewall = false;
      listenAddress = "127.0.0.1";
      enabledCollectors = ["systemd" "textfile"];
      extraFlags = ["--collector.textfile.directory=${metricsDir}"];
    };

    # Directory for textfile collector metrics written by systemd services and backup jobs
    systemd.tmpfiles.rules = [
      "d ${metricsDir} 0755 root root -"
    ];

    # Write deploy timestamp metric so Grafana can show deploy age per host.
    # Triggered on boot and on every config change via restartTriggers.
    systemd.services.prometheus-nixos-deploy = {
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      restartTriggers = [
        config.system.nixos.version
        (config.system.configurationRevision or "")
      ];
      script = ''
        version=$(cat /run/current-system/nixos-version)
        echo "nixos_deploy_timestamp{version=\"$version\"} $(date +%s)" > ${metricsDir}/deploy.prom.tmp
        mv ${metricsDir}/deploy.prom.tmp ${metricsDir}/deploy.prom
      '';
    };

    systemd.services.prometheus-node-exporter.serviceConfig = {
      Restart = "always";
      RestartSec = 5;
    };

    # Scrape target for prometheus
    homelab.scrapeTargets = [
      {
        job = "node";
        metricsPath = "/metrics/node";
      }
    ];

    # Metrics nginx proxy for all exporters.
    # Path-based routing allows single firewall port for all metrics.
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [services.metrics.port];

    services.nginx = {
      enable = true;
      virtualHosts."metrics" = {
        extraConfig = ''
          allow ${services.netbird.subnet};
          deny all;
        '';
        locations."/metrics/node" = {
          proxyPass = "http://127.0.0.1:9100/metrics";
        };
        listen = [
          {
            addr = "0.0.0.0";
            port = services.metrics.port;
          }
        ];
      };
    };
  };
}

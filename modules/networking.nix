{
  config,
  lib,
  ...
}: let
  services = config.serviceConfig;
  host = config.hostConfig.self;
  domain = services.global.domain;
  hostServices = host.services or {};
  serviceIPs = lib.mapAttrsToList (_: service: service.ip) hostServices;
  hasServices = hostServices != {};
in {
  # Avoid collision of the dhcp with the sysystemd.network
  networking = {
    useDHCP = lib.mkForce false;
    useNetworkd = lib.mkForce true;
  };

  # Do not wait to long for interfaces to become online,
  # this is especially handy for notebooks on wifi,
  # where the eth interface is disconnected
  boot.initrd.systemd.network.wait-online.enable = false;

  networking = {
    hostName = config.hostConfig.self.hostName;
    firewall.enable = true;
    # Use nftables instead of iptables (modern, better performance)
    nftables.enable = true;
  };

  services.resolved = {
    enable = true;
    extraConfig = lib.mkDefault ''
      [Resolve]
      # Backup if no interface provides DNS servers
      FallbackDNS=1.1.1.1 8.8.8.8
      # Keeps compatibility with apps expecting DNS on 127.0.0.53
      DNSStubListener=yes
      # Reduces noise on the network
      MulticastDNS=no
      # Reduces noise on the network
      LLMNR=no
      # DNS caching enabled for Netbird
      Cache=yes
      DNSSEC=allow-downgrade
    '';
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
      };
      "99-all-wifi" = {
        matchConfig.Type = "wlan";
        DHCP = "yes";
      };
    };
  };

  # Local DNS resolution for service hostnames
  networking.hosts =
    lib.mapAttrs' (
      name: service:
        lib.nameValuePair service.ip ["${name}.${domain}"]
    )
    hostServices;

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
        # Don't modify resolv.conf directly
        rc-manager = "resolvconf";
        # Faster connection establishment
        dhcp = "dhclient";
      };
    };
  };

  # iwd for wifi, used by both NetworkManager and standalone systemd-networkd
  networking.wireless.iwd = {
    enable = true;
    settings = {
      Network = {
        EnableIPv6 = true;
      };
      Settings = {
        AutoConnect = true;
      };
    };
  };

  # Metrics nginx proxy for all exporters.
  # Path-based routing allows single firewall port for all metrics.
  networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [services.metrics.port];

  services.nginx = {
    enable = true;
    virtualHosts."metrics".listen = [
      {
        addr = "0.0.0.0";
        port = services.metrics.port;
      }
    ];
  };
}

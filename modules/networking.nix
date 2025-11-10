{
  config,
  lib,
  pkgs,
  ...
}: {
  # Avoid collision of the dhcp with the sysystemd.network
  networking = {
    useDHCP = lib.mkForce false;
    useNetworkd = lib.mkForce true;
  };

  # Netbird configuration using multi-instance support
  # Only homelab network managed by Nix
  # Company network configured separately via devops-provided config
  services.netbird.clients = {
    homelab = {
      port = 51820;
      # Interface will be: nb-homelab
      # Setup key: /var/lib/netbird-homelab/setup-key
      # State: /var/lib/netbird-homelab/
    };
  };

  # Automatic enrollment using setup key on first boot
  # The setup key is injected during deployment by nixos-install script
  systemd.services.netbird-homelab-enroll = {
    description = "Enroll Netbird homelab client with setup key";
    wantedBy = ["multi-user.target"];
    after = ["netbird-homelab.service"];
    requires = ["netbird-homelab.service"];

    # Only run if setup key file exists (meaning we need to enroll)
    unitConfig.ConditionPathExists = "/var/lib/netbird-homelab/setup-key";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 5;
      StartLimitBurst = 3;
      ExecStart = let
        setupKeyFile = "/var/lib/netbird-homelab/setup-key";
        daemonAddr = "unix:///var/run/netbird-homelab/sock";
      in
        pkgs.writeShellScript "netbird-enroll" ''
          set -euo pipefail

          # Enroll with setup key, specifying the correct daemon address
          ${pkgs.netbird}/bin/netbird up \
            --daemon-addr ${daemonAddr} \
            --setup-key "$(cat ${setupKeyFile})"

          # Only reached after successful enrollment
          rm -f ${setupKeyFile}
        '';
    };
  };

  # Do not wait to long for interfaces to become online,
  # this is especially handy for notebooks on wifi,
  # where the eth interface is disconnected
  boot.initrd.systemd.network.wait-online.enable = false;
  systemd.network.wait-online = {
    anyInterface = true;
    timeout = 10;
  };

  networking = {
    hostName = config.hosts.self.hostName;
    firewall.enable = true;
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
    networks = {
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

  # NetworkManager configuration
  networking.networkmanager = {
    enable = true;
    # Don't let NetworkManager manage systemd-networkd interfaces
    # Include nb-* pattern to cover both homelab and any manually configured networks
    unmanaged = ["nb-*"];
    # Enhanced DNS handling
    dns = "systemd-resolved";
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
}

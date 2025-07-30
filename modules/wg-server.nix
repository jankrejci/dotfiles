{
  config,
  lib,
  ...
}: let
  wgPort = 51820;
  dnsPort = 53;
  domain = "vpn";
in {
  # Enable wg listenning port
  networking.firewall.allowedUDPPorts = [wgPort];

  # Create list of all peers for wg server
  systemd.network.netdevs."10-wg0" = {
    wireguardConfig.ListenPort = wgPort;
    wireguardPeers = let
      makePeer = host: {
        PublicKey = host.wgPublicKey;
        AllowedIPs = [host.ipAddress];
        PersistentKeepalive = 25;
      };
    in
      builtins.map makePeer (builtins.attrValues config.hosts);
  };

  systemd.network.networks."wg0" = {
    networkConfig = {
      IPMasquerade = "ipv4";
      IPv4Forwarding = true;
    };
  };

  # Enable ports for dns withing the wg vpn
  networking.firewall.interfaces."wg0" = {
    allowedUDPPorts = [dnsPort];
    allowedTCPPorts = [dnsPort];
  };

  services.coredns = {
    enable = true;
    config = ''
      # VPN hosts with custom mappings
      .:53 {
        # Bind only to VPN interfaces
        bind wg0

        # Custom host mappings
        hosts /etc/coredns/vpn-hosts {
          ttl 300
          reload 5s
          fallthrough
        }

        # Forward external queries
        forward . 1.1.1.1 8.8.8.8 {
          prefer_udp
        }

        # Performance and reliability
        cache 300
        loop
        errors
        log

        # Health endpoints
        health :8080
        prometheus :9153
      }
    '';
  };

  # Create a list of all ip - host pairs to be resolved
  environment.etc."coredns/vpn-hosts".text = let
    makeHostEntry = hostName: hostConfig: hostConfig.ipAddress + " " + hostName + "." + domain;
  in
    builtins.concatStringsSep "\n" (lib.mapAttrsToList makeHostEntry config.hosts) + "\n";
}

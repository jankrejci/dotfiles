{ config, lib, ... }:
let
  wgPort = 51820;
  dnsPort = 53;
  domain = "vpn";
in
{
  # Enable wg listenning port
  networking.firewall.allowedUDPPorts = [ wgPort ];

  # Create list of all peers for wg server
  systemd.network.netdevs."10-wg0" = {
    wireguardConfig.ListenPort = wgPort;
    wireguardPeers =
      let
        makePeer = host: {
          PublicKey = host.wgPublicKey;
          AllowedIPs = [ host.ipAddress ];
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
  networking.firewall.interfaces = {
    "wg0".allowedUDPPorts = [ dnsPort ];
    "wg0".allowedTCPPorts = [ dnsPort ];
  };

  services.dnsmasq = {
    enable = true;
    alwaysKeepRunning = true;
    settings = {
      "port" = "${toString dnsPort}";
      "domain-needed" = true;
      "bogus-priv" = true;
      "domain" = domain;

      "expand-hosts" = false;
      "addn-hosts" = "/etc/dnsmasq-hosts";

      "interface" = "wg0";
      "listen-address" = [ config.hosts.self.ipAddress ];

      # Disable DHCP service
      "no-dhcp-interface" = "wg0";
      server = [
        "1.1.1.1"
        "8.8.8.8"
      ];
    };
  };

  # Avoid collision between systemd-resolve and dnsmasq
  services.resolved = {
    extraConfig = ''
      [Resolve]
      Cache=no
      DNSStubListener=no
    '';
  };

  # Create a list of all ip - host pairs to be resolved
  environment.etc."dnsmasq-hosts".text =
    let
      makeHostEntry = hostName: hostConfig: hostConfig.ipAddress + " " + hostName + "." + domain;
    in
    builtins.concatStringsSep "\n" (lib.mapAttrsToList makeHostEntry config.hosts) + "\n";

  # Restart dnsmasq when /etc/dnsmasq-hosts changes
  systemd.services.dnsmasq.restartTriggers = [
    config.environment.etc."dnsmasq-hosts".source
  ];
}

{ config, lib, ... }:
let
  domain = "vpn";
  nameServers = [ "127.0.0.53" "1.1.1.1" "8.8.8.8" ];
  privateKeyPath = "/var/lib/wireguard/wg-key";
in
{
  # Avoid collision of the dhcp with the sysystemd.network
  networking = {
    useDHCP = lib.mkForce false;
    useNetworkd = lib.mkForce true;
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
    nameservers = nameServers;
  };

  services.resolved = {
    enable = true;
    extraConfig = lib.mkDefault ''
      [Resolve]
      DNS=127.0.0.53
      FallbackDNS=1.1.1.1 8.8.8.8
      DNSStubListener=yes
      MulticastDNS=no
      LLMNR=no
      Cache=no
      DNSSEC=allow-downgrade
    '';
  };

  # Configure the wg vpn
  systemd.network = {
    enable = true;
    netdevs = {
      "10-wg0" = {
        netdevConfig = {
          Kind = "wireguard";
          Name = "wg0";
          # WG adds 80 bytes so the total frame size is 1300
          MTUBytes = "1220";
        };
        wireguardConfig = {
          PrivateKeyFile = privateKeyPath;
        };
        wireguardPeers = [
          {
            PublicKey = config.hosts.vpsfree.wgPublicKey;
            AllowedIPs = [ "192.168.99.0/24" ];
            Endpoint = "37.205.13.227:51820";
            PersistentKeepalive = 25;
          }
        ];
      };
    };
    networks = {
      "10-wg0" = {
        matchConfig.Name = "wg0";
        address = [ "${config.hosts.self.ipAddress}/24" ];
        DHCP = "no";
        dns = [ "192.168.99.1" ];
        domains = [ "~${domain}" ];
      };
      # Enable dhcp via sysystemd.network
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
}

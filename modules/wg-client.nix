{ lib, config, hostConfig, hostInfo, ... }:
{
  # Avoid collision with the sysystemd.network
  networking = {
    useDHCP = lib.mkForce false;
    useNetworkd = lib.mkForce true;
  };

  systemd.network = {
    enable = lib.mkForce true;
    netdevs = {
      "10-wg0" = {
        netdevConfig = {
          Kind = "wireguard";
          Name = "wg0";
          # WG adds 80 bytes so the total frame size is 1300
          MTUBytes = "1220";
        };
        wireguardConfig = {
          PrivateKeyFile = config.sops.secrets."wg_private_key".path;
        };
        wireguardPeers = [
          {
            PublicKey = hostInfo.vpsfree.wgPublicKey;
            AllowedIPs = [ "192.168.99.0/24" ];
            Endpoint = "37.205.13.227:51820";
            PersistentKeepalive = 25;
          }
        ];
      };
    };
    networks.wg0 = {
      matchConfig.Name = "wg0";
      address = [ "${hostConfig.ipAddress}/24" ];
      DHCP = "no";
      dns = [ "192.168.99.1" ];
      domains = [ "~home" ];
    };
  };
  services.resolved = {
    # Disable caching as it fails to resolve name over wg somehow
    extraConfig = ''
      [Resolve]
      Cache=no
      Domains=~home
    '';
  };

}

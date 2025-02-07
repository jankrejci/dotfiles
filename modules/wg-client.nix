{ config, hostConfig, hostInfo, ... }:
{
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
          PrivateKeyFile = config.sops.secrets."hosts/${hostConfig.hostName}/wg_private_key".path;
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
      routingPolicyRules = [{
        To = "192.168.99.0/24";
        Table = 99;
        Priority = 50;
      }];
      routes = [{
        Destination = "192.168.99.0/24";
        Table = 99;
      }];
      address = [ "${hostConfig.ipAddress}/24" ];
      DHCP = "no";
      dns = [ "192.168.99.1:5454" ];
      domains = [ "home" ];
    };
  };
}

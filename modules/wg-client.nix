{ config, hostConfig, hostInfo, ... }:
{
  networking.wg-quick.interfaces.wg0 =
    {
      address = [ "${hostConfig.ipAddress}/24" ];
      privateKeyFile = config.sops.secrets."hosts/${hostConfig.hostName}/wg_private_key".path;
      dns = [ "192.168.99.1" ];

      peers = [
        {
          # Public key of the server
          publicKey = hostInfo.vpsfree.wgPublicKey;
          allowedIPs = [ "192.168.99.0/24" ];
          endpoint = "37.205.13.227:51820";
          # Send keepalives every 25 seconds. Important to keep NAT tables alive.
          persistentKeepalive = 25;
        }
      ];
    };

  systemd.services."wg-quick@wg0".serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };
}

{ config, hostConfig, ... }:
{
  networking.wg-quick.interfaces.wg0 = {
    address = [ "${hostConfig.ipAddress}/24" ];
    privateKeyFile = config.sops.secrets.wg-private-key.path;
    dns = [ "192.168.99.11" ];

    peers = [
      {
        # Public key of the server
        publicKey = "iWfrqdXV4bDQOCfhlZ2KRS7eq2B/QI440HylPrzJUww=";
        allowedIPs = [ "192.168.99.0/24" "1.1.1.1" "8.8.8.8" ];
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

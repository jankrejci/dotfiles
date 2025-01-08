{ ... }:
{
  networking.wg-quick.interfaces.wg0 = {
    peers = [
      {
        # Public key of the server
        publicKey = "QMz5SM4JuQrW+ms9N9dtihS9TYbhWzlXQHjr/X4oRGg=";
        allowedIPs = [ "192.168.99.0/24" "1.1.1.1" "8.8.8.8" ];
        endpoint = "37.205.13.227:51820";
        # Send keepalives every 25 seconds. Important to keep NAT tables alive.
        persistentKeepalive = 25;
      }
    ];
  };
}

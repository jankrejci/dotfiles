{ ... }:
{
  networking.firewall.allowedUDPPorts = [ 51820 ];

  networking.wireguard.interfaces.wg0 = {
    # Determines the IP address and subnet of the server's end of the tunnel interface.
    ips = [ "192.168.99.1/24" ];
    # The port that WireGuard listens to. Must be accessible by the client.
    listenPort = 51820;
    # Path to the private key file.
    privateKeyFile = "/home/jkr/.wg/jkr-vpsfree";
    peers = [
      {
        # jkr@rpi4
        publicKey = "RGw8RUoKUA1VirhvJHQZEmgzRgyfqCQIlzudkAei4C0=";
        allowedIPs = [ "192.168.99.2/32" ];
      }
      {
        # jkr@optiplex
        publicKey = "6QNJxFoSDKwqQjF6VgUEWP5yXXe4J3DORGo7ksQscFA=";
        allowedIPs = [ "192.168.99.3/32" ];
      }
      {
        # jkr@thinkpad
        publicKey = "IzW6yPZJdrBC6PtfSaw7k4hjH+b/GjwvwiDLkLevLDI=";
        allowedIPs = [ "192.168.99.4/32" ];
      }
      {
        # jkr@android
        publicKey = "HP+nPkrKwAxvmXjrI9yjsaGRMVXqt7zdcBGbD2ji83g=";
        allowedIPs = [ "192.168.99.5/32" ];
      }
      # {
      #   # jkr@latitude
      #   publicKey = "";
      #   allowedIPs = [ "192.168.99.5/32" ];
      # }
    ];
  };
}

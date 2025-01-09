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
        # jkr@latitude
        publicKey = "ggj+uqF/vij5V+fA5r9GIv5YuT9hX7OBp+lAGYh5SyQ=";
        allowedIPs = [ "192.168.99.5/32" ];
      }
      {
        # jkr@android
        publicKey = "HP+nPkrKwAxvmXjrI9yjsaGRMVXqt7zdcBGbD2ji83g=";
        allowedIPs = [ "192.168.99.6/32" ];
      }
    ];
  };

  networking.firewall.interfaces."wg0".allowedUDPPorts = [ 53 ];
  networking.firewall.interfaces."wg0".allowedTCPPorts = [ 53 ];
  services.dnsmasq = {
    enable = true;
    alwaysKeepRunning = true;
    settings = {
      # Basic settings
      "domain-needed" = true;
      "bogus-priv" = true;
      "expand-hosts" = false;
      "domain" = "home";

      "addn-hosts" = "/etc/dnsmasq-hosts";

      # Listen on specific interface and IP
      "interface" = "wg0";
      "listen-address" = [
        "127.0.0.1"
        "192.168.99.1"
      ];

      # Disable DHCP service
      "no-dhcp-interface" = "wg0";

      server = [
        "1.1.1.1" # Cloudflare DNS
        "8.8.8.8" # Google DNS
      ];
    };
  };

  environment.etc."dnsmasq-hosts".text = ''
    192.168.99.1 vpsfree.home
    192.168.99.2 rpi4.home
  '';
}

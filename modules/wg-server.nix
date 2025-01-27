{ config, hostConfig, hostInfo, ... }:
{
  networking.firewall.allowedUDPPorts = [ 51820 ];
  networking.wireguard.interfaces.wg0 = {
    # Determines the IP address and subnet of the server's end of the tunnel interface.
    ips = [ "${hostConfig.ipAddress}/24" ];
    # The port that WireGuard listens to. Must be accessible by the client.
    listenPort = 51820;
    # Path to the private key file.
    privateKeyFile = config.sops.secrets."hosts/${hostConfig.hostName}/wg_private_key".path;
    peers =
      let
        makePeer = host: {
          publicKey = host.wgPublicKey;
          allowedIPs = [ host.ipAddress ];
        };
      in
      builtins.map makePeer (builtins.attrValues hostInfo);
  };

  systemd.services."wg-quick@wg0".serviceConfig = {
    Restart = "always";
    RestartSec = 5;
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
        "${hostConfig.ipAddress}"
      ];

      # Disable DHCP service
      "no-dhcp-interface" = "wg0";

      server = [
        "1.1.1.1" # Cloudflare DNS
        "8.8.8.8" # Google DNS
      ];
    };
  };

  environment.etc."dnsmasq-hosts".text =
    let
      makeHostEntry = name: hostInfo.${name}.ipAddress + " " + name + ".home";
    in
    builtins.concatStringsSep "\n" (builtins.map makeHostEntry (builtins.attrNames hostInfo)) + "\n";
}

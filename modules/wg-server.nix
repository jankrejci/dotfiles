{ config, hostConfig, hostInfo, ... }:
let
  wgPort = 51820;
in
{

  networking.firewall.allowedUDPPorts = [ wgPort ];
  networking.useNetworkd = true;

  systemd.network = {
    enable = true;
    netdevs = {
      "50-wg0" = {
        netdevConfig = {
          Kind = "wireguard";
          Name = "wg0";
          # WG adds 80 bytes so the total frame size is 1300
          MTUBytes = "1220";
        };
        wireguardConfig = {
          PrivateKeyFile = config.sops.secrets."hosts/${hostConfig.hostName}/wg_private_key".path;
          ListenPort = wgPort;
        };
        wireguardPeers =
          let
            makePeer = host: {
              PublicKey = host.wgPublicKey;
              AllowedIPs = [ host.ipAddress ];
              PersistentKeepalive = 25;
            };
          in
          builtins.map makePeer (builtins.attrValues hostInfo);
      };
    };
    networks.wg0 = {
      matchConfig.Name = "wg0";
      address = [ "${hostConfig.ipAddress}/24" ];
      networkConfig = {
        IPMasquerade = "ipv4";
        IPv4Forwarding = true;
      };
    };
  };

  services.resolved = {
    # Disable the default 127.0.0.53:53 to avoid collision with dnsmasq
    extraConfig = ''
      DNSStubListener=no
    '';
  };

  networking.firewall.interfaces."wg0".allowedUDPPorts = [ 53 ];
  networking.firewall.interfaces."wg0".allowedTCPPorts = [ 53 ];
  services.dnsmasq = {
    enable = true;
    alwaysKeepRunning = true;
    settings = {
      "domain-needed" = true;
      "bogus-priv" = true;
      "domain" = "home";

      "expand-hosts" = false;
      "addn-hosts" = "/etc/dnsmasq-hosts";

      "interface" = "wg0";
      "listen-address" = [
        "127.0.0.1"
        hostConfig.ipAddress
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

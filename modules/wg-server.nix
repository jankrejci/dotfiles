{ config, hostConfig, hostInfo, ... }:
let
  wgPort = 51820;
  dnsPort = 53;
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
          PrivateKeyFile = config.sops.secrets."wg_private_key".path;
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
      dns = [ "${hostConfig.ipAddress}" ];
      domains = [ "~home" ];
      networkConfig = {
        IPMasquerade = "ipv4";
        IPv4Forwarding = true;
      };
    };
  };

  networking.firewall.interfaces = {
    "wg0".allowedUDPPorts = [ dnsPort ];
    "wg0".allowedTCPPorts = [ dnsPort ];
  };
  services.dnsmasq = {
    enable = true;
    alwaysKeepRunning = true;
    settings = {
      "port" = "${toString dnsPort}";
      "domain-needed" = true;
      "bogus-priv" = true;
      "domain" = "home";

      "expand-hosts" = false;
      "addn-hosts" = "/etc/dnsmasq-hosts";

      "interface" = "wg0";
      "listen-address" = [ hostConfig.ipAddress ];

      # Disable DHCP service
      "no-dhcp-interface" = "wg0";
      server = [
        "1.1.1.1"
        "8.8.8.8"
      ];
    };
  };

  services.resolved = {
    extraConfig = ''
      [Resolve]
      Cache=no
      DNSStubListener=no
    '';
  };

  environment.etc."dnsmasq-hosts".text =
    let
      makeHostEntry = name: hostInfo.${name}.ipAddress + " " + name + ".home";
    in
    builtins.concatStringsSep "\n" (builtins.map makeHostEntry (builtins.attrNames hostInfo)) + "\n";
}

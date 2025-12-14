{lib, ...}: let
  vpsfreePublicKey = lib.fileContents ../wireguard-keys/vpsfree-public;
in {
  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  hardware.cpu.intel.updateMicrocode = true;

  # Enable processes collector for detailed monitoring (systemd already enabled in common.nix)
  services.prometheus.exporters.node.enabledCollectors = lib.mkForce ["systemd" "processes"];

  # WireGuard exporter for wg0 tunnel monitoring
  services.prometheus.exporters.wireguard = {
    enable = true;
    port = 9586;
    listenAddress = "127.0.0.1";
    openFirewall = false;
    latestHandshakeDelay = true;
    verbose = false;
  };

  # Wireguard metrics endpoint via common metrics vhost
  services.nginx.virtualHosts."metrics".locations."/metrics/wireguard" = {
    proxyPass = "http://127.0.0.1:9586/metrics";
  };

  # WireGuard tunnel to vpsfree for NetBird self-hosted
  # thinkcenter (behind NAT) -> vpsfree (public gateway)
  networking.firewall.allowedUDPPorts = [51821];

  systemd.network.netdevs."50-wg0" = {
    netdevConfig = {
      Kind = "wireguard";
      Name = "wg0";
    };
    wireguardConfig = {
      PrivateKeyFile = "/var/lib/wireguard/wg-thinkcenter-private";
      ListenPort = 51821;
    };
    wireguardPeers = [
      {
        PublicKey = vpsfreePublicKey;
        AllowedIPs = ["192.168.99.2/32"];
        Endpoint = "wg.krejci.io:51821";
        PersistentKeepalive = 25;
      }
    ];
  };

  systemd.network.networks."50-wg0" = {
    matchConfig.Name = "wg0";
    address = ["192.168.99.1/24"];
    networkConfig.DHCP = "no";
  };
}

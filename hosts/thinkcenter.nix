{lib, ...}: let
  vpsfreePublicKey = lib.fileContents ../wireguard-keys/vpsfree-public;
in {
  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  hardware.cpu.intel.updateMicrocode = true;

  # WireGuard tunnel to vpsfree for NetBird self-hosted
  # thinkcenter (behind NAT) -> vpsfree (public gateway)
  networking.firewall.allowedUDPPorts = [51820];

  systemd.network.netdevs."50-wg-vpsfree" = {
    netdevConfig = {
      Kind = "wireguard";
      Name = "wg-vpsfree";
    };
    wireguardConfig = {
      PrivateKeyFile = "/root/secrets/wg-thinkcenter-private";
      ListenPort = 51820;
    };
    wireguardPeers = [
      {
        PublicKey = vpsfreePublicKey;
        AllowedIPs = ["10.100.0.2/32"];
        Endpoint = "wg.krejci.io:51820";
        PersistentKeepalive = 25;
      }
    ];
  };

  systemd.network.networks."50-wg-vpsfree" = {
    matchConfig.Name = "wg-vpsfree";
    address = ["10.100.0.1/30"];
    networkConfig.DHCP = "no";
  };
}

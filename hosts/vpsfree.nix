{
  lib,
  pkgs,
  ...
}: let
  domain = "krejci.io";
  thinkCenterPublicKey = lib.fileContents ../wireguard-keys/thinkcenter-public;
  nasHost = "172.16.130.249";
  nasPath = "/nas/6057";
  mountPoint = "/mnt/nas-backup";
in {
  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  # vpsAdminOS containers don't support tmpfs on /tmp with systemd mount namespacing
  boot.tmp.useTmpfs = lib.mkForce false;

  systemd.settings.Manager.DefaultTimeoutStartSec = "900s";

  # Avoid collision between networking and vpsadminos module
  systemd.network.networks."98-all-ethernet".DHCP = "no";

  # Disable wait-online - network is managed by vpsAdminOS host, not systemd-networkd
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  # Disable systemd-hostnamed - fails in container trying to access /sys/firmware/acpi
  systemd.services.systemd-hostnamed.enable = lib.mkForce false;

  # There is no DHCP, so fixed dns is needed
  networking.nameservers = ["1.1.1.1" "8.8.8.8"];

  # Backup storage - NFS mount from NAS
  fileSystems.${mountPoint} = {
    device = "${nasHost}:${nasPath}";
    fsType = "nfs";
    options = ["nofail"];
  };

  # Bind mount borg repos from NAS
  fileSystems."/var/lib/borg-repos" = {
    device = "${mountPoint}/borg-repos";
    fsType = "none";
    options = ["bind" "x-systemd.requires=mnt-nas\\x2dbackup.mount"];
  };

  # Ensure base directory exists on NAS
  systemd.tmpfiles.rules = [
    "d ${mountPoint}/borg-repos 0755 borg borg -"
    "d ${mountPoint}/borg-repos/immich 0700 borg borg -"
  ];

  # Create dedicated borg user for backup operations
  users.users.borg = {
    isSystemUser = true;
    group = "borg";
    shell = "${pkgs.bash}/bin/bash";
    home = "/var/lib/borg";
    createHome = true;
  };

  users.groups.borg = {};

  # Install borgbackup for borg serve command
  environment.systemPackages = with pkgs; [
    borgbackup
  ];

  # WireGuard tunnel to thinkcenter for NetBird self-hosted
  # vpsfree (public gateway) <- thinkcenter (behind NAT)
  networking.firewall.allowedUDPPorts = [51821];

  systemd.network.netdevs."50-wg0" = {
    netdevConfig = {
      Kind = "wireguard";
      Name = "wg0";
    };
    wireguardConfig = {
      PrivateKeyFile = "/var/lib/wireguard/wg-vpsfree-private";
      ListenPort = 51821;
    };
    wireguardPeers = [
      {
        PublicKey = thinkCenterPublicKey;
        AllowedIPs = ["10.100.0.1/32"];
        PersistentKeepalive = 25;
      }
    ];
  };

  systemd.network.networks."50-wg0" = {
    matchConfig.Name = "wg0";
    address = ["10.100.0.2/30"];
    networkConfig.DHCP = "no";
  };

  # Test endpoint for Netbird Networks DNS testing
  # Only accessible via nb-homelab interface
  networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [443];

  services.nginx.virtualHosts."test.${domain}" = {
    listenAddresses = ["0.0.0.0"];
    forceSSL = true;
    useACMEHost = domain;
    extraConfig = ''
      allow 100.76.0.0/16;
      deny all;
    '';
    locations."/".return = "200 'Hello from vpsfree test endpoint'";
  };
}

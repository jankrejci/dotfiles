{
  lib,
  pkgs,
  ...
}: let
  nasHost = "172.16.130.249";
  nasPath = "/nas/6057";
  mountPoint = "/mnt/nas-backup";
in {
  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  systemd.extraConfig = ''
    DefaultTimeoutStartSec=900s
  '';

  # Avoid collision between networking and vpsadminos module
  systemd.network.networks."98-all-ethernet".DHCP = "no";

  # Disable wait-online - network is managed by vpsAdminOS host, not systemd-networkd
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

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
}

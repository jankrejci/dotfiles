{
  config,
  pkgs,
  lib,
  ...
}: let
  nasHost = "172.16.130.249";
  nasPath = "/nas/6057";
  mountPoint = "/mnt/nas-backup";
in {
  # Mount NAS storage for backup repositories
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

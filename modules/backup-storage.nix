{
  config,
  pkgs,
  lib,
  ...
}: let
  nasHost = "172.16.130.249";
  nasPath = "/nas/6057";
  mountPoint = "/mnt/nas-backup";
  repoBasePath = "${mountPoint}/borg-repos";
in {
  # Mount NAS storage for backup repositories
  fileSystems.${mountPoint} = {
    device = "${nasHost}:${nasPath}";
    fsType = "nfs";
    options = ["nofail"];
  };

  # Ensure base directory for borg repositories exists
  systemd.tmpfiles.rules = [
    "d ${repoBasePath} 0755 borg borg -"
    "d ${repoBasePath}/immich 0700 borg borg -"
  ];

  # Create dedicated borg user for backup operations
  users.users.borg = {
    isSystemUser = true;
    group = "borg";
    shell = "${pkgs.bash}/bin/bash";
  };

  users.groups.borg = {};

  # Install borgbackup for borg serve command
  environment.systemPackages = with pkgs; [
    borgbackup
  ];
}

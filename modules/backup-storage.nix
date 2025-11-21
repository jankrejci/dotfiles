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
    home = "/var/lib/borg";
    createHome = true;
  };

  users.groups.borg = {};

  # Install borgbackup for borg serve command
  environment.systemPackages = with pkgs; [
    borgbackup
  ];

  # Oneshot service to initialize borg repository
  systemd.services.borg-init-immich = {
    description = "Initialize Borg repository for Immich backups";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];

    # Only run if passphrase exists and repo not initialized
    unitConfig = {
      ConditionPathExists = [
        "/root/secrets/borg-passphrase-env"
        "!${repoBasePath}/immich/config"
      ];
    };

    serviceConfig = {
      Type = "oneshot";
      User = "borg";
      RemainAfterExit = true;
      EnvironmentFile = "/root/secrets/borg-passphrase-env";
    };

    script = ''
      ${pkgs.borgbackup}/bin/borg init --encryption=repokey-blake2 ${repoBasePath}/immich
      echo "Borg repository initialized successfully"
    '';
  };
}

{
  config,
  pkgs,
  lib,
  ...
}: let
  domain = "krejci.io";
  immichDomain = "immich.${domain}";
  immichPort = 2283;
  # Second disk for Immich data (NVMe)
  # Assumes partition is already created with label "disk-immich-luks"
  luksDevice = "/dev/disk/by-partlabel/disk-immich-luks";

  # Backup configuration
  backupDir = "/var/backup/immich-db";
  borgRepo = "ssh://borg@vpsfree.krejci.io/mnt/nas-backup/borg-repos/immich";
in {
  # Install borgbackup for backup operations
  environment.systemPackages = with pkgs; [
    borgbackup
    (pkgs.writeShellScriptBin "restore-immich-backup" ''
      if [ $# -eq 0 ]; then
        echo "Usage: restore-immich-backup ARCHIVE_NAME"
        echo ""
        echo "Available backups:"
        borg-job-immich list
        exit 1
      fi

      readonly ARCHIVE="$1"

      echo "WARNING: This will restore Immich data from backup: $ARCHIVE"
      echo "Current data will be overwritten!"
      read -r -p "Continue? (yes/no): " confirm

      if [ "$confirm" != "yes" ]; then
        echo "Restore cancelled"
        exit 0
      fi

      echo "Stopping Immich..."
      systemctl stop immich-server

      echo "Restoring files..."
      cd / && borg-job-immich extract --progress ::$ARCHIVE var/lib/immich var/backup/immich-db

      echo "Restoring database..."
      sudo -u postgres ${config.services.postgresql.package}/bin/pg_restore -d immich --clean ${backupDir}/immich.dump

      echo "Starting Immich..."
      systemctl start immich-server

      echo "Restore complete!"
    '')
  ];
  # Allow HTTPS on VPN interface (nginx proxies to Immich for both web and mobile)
  networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [443];

  # NVMe data disk - TPM encrypted, not touched during deployment
  boot.initrd.luks.devices."immich-data" = {
    device = luksDevice;
    allowDiscards = true;
  };

  fileSystems."/var/lib/immich" = {
    device = "/dev/mapper/immich-data";
    fsType = "ext4";
    options = ["defaults" "nofail"];
  };

  services.immich = {
    enable = true;
    # Listen on localhost only, accessed via nginx proxy
    host = "127.0.0.1";
    port = immichPort;
    # Media stored on dedicated NVMe disk at /var/lib/immich (default)
    environment.PUBLIC_IMMICH_SERVER_URL = "https://share.${domain}";
  };

  # Ensure required directory structure exists on the data disk
  systemd.tmpfiles.rules = [
    "d /var/lib/immich/upload 0755 immich immich -"
    "d /var/lib/immich/library 0755 immich immich -"
    "d /var/lib/immich/thumbs 0755 immich immich -"
    "d /var/lib/immich/profile 0755 immich immich -"
    "d /var/lib/immich/encoded-video 0755 immich immich -"
    "d /var/lib/immich/backups 0755 immich immich -"
    "f /var/lib/immich/upload/.immich 0644 immich immich -"
    "f /var/lib/immich/library/.immich 0644 immich immich -"
    "f /var/lib/immich/thumbs/.immich 0644 immich immich -"
    "f /var/lib/immich/profile/.immich 0644 immich immich -"
    "f /var/lib/immich/encoded-video/.immich 0644 immich immich -"
    "f /var/lib/immich/backups/.immich 0644 immich immich -"
    "d ${backupDir} 0700 postgres postgres -"
  ];

  # PostgreSQL database dump service
  systemd.services.immich-db-dump = {
    description = "Dump Immich PostgreSQL database";
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      ExecStart = "${config.services.postgresql.package}/bin/pg_dump -Fc -f ${backupDir}/immich.dump immich";
    };
  };

  # Borg backup configuration
  services.borgbackup.jobs.immich = {
    paths = [
      "/var/lib/immich"
      backupDir
    ];
    exclude = [
      "/var/lib/immich/thumbs"
      "/var/lib/immich/encoded-video"
    ];
    repo = borgRepo;
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat /root/secrets/borg-passphrase";
    };
    environment = {
      BORG_RSH = "ssh -i /root/.ssh/borg-backup-key";
    };
    compression = "auto,zstd";
    startAt = "daily";
    # Run at 2 AM
    persistentTimer = true;
    preHook = ''
      systemctl start immich-db-dump.service
    '';
    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };
  };

  # Nginx reverse proxy - accessible via immich.<domain>
  services.nginx = {
    enable = true;
    virtualHosts.${immichDomain} = {
      listenAddresses = ["0.0.0.0"];
      # Enable HTTPS with Let's Encrypt wildcard certificate
      forceSSL = true;
      useACMEHost = "${domain}";
      # Allow large file uploads for photos and videos
      extraConfig = ''
        client_max_body_size 1G;
      '';
      locations."/" = {
        proxyPass = "http://localhost:${toString immichPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}

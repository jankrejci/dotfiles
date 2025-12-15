# Immich photo library with homelab enable flag
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.immich;
  services = config.homelab.services;
  host = config.homelab.host;
  domain = services.global.domain;
  immichDomain = "${services.immich.subdomain}.${domain}";
  httpsPort = services.https.port;

  # Internal metrics ports for exporters
  immichApiMetricsPort = 8081;
  immichMicroservicesMetricsPort = 8082;
  postgresMetricsPort = 9187;
  redisMetricsPort = 9121;
  nginxMetricsPort = 9113;

  # Second disk for Immich data (NVMe)
  # Assumes partition is already created with label "disk-immich-luks"
  luksDevice = "/dev/disk/by-partlabel/disk-immich-luks";

  # Backup configuration
  backupDir = "/var/backup/immich-db";
in {
  options.homelab.immich = {
    # Default true preserves existing behavior during transition
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Immich photo library";
    };
  };

  config = lib.mkIf cfg.enable {
    # Scrape target registration will be added in Phase 4 when modules/default.nix
    # is used and homelab.monitoring options are available to all hosts.

    # Install borgbackup for backup operations
    environment.systemPackages = with pkgs; [
    borgbackup
    (pkgs.writeShellScriptBin "restore-immich-backup" ''
      if [ $# -lt 2 ]; then
        echo "Usage: restore-immich-backup <remote|local> ARCHIVE_NAME"
        echo ""
        echo "Available remote backups:"
        borg-job-immich-remote list
        echo ""
        echo "Available local backups:"
        borg-job-immich-local list
        exit 1
      fi

      readonly SOURCE="$1"
      readonly ARCHIVE="$2"

      case "$SOURCE" in
        remote)
          BORG_CMD="borg-job-immich-remote"
          ;;
        local)
          BORG_CMD="borg-job-immich-local"
          ;;
        *)
          echo "Error: Source must be 'remote' or 'local'"
          exit 1
          ;;
      esac

      echo "WARNING: This will restore Immich data from $SOURCE backup: $ARCHIVE"
      echo "Current data will be overwritten!"
      read -r -p "Continue? (yes/no): " confirm

      if [ "$confirm" != "yes" ]; then
        echo "Restore cancelled"
        exit 0
      fi

      echo "Stopping Immich..."
      systemctl stop immich-server

      echo "Restoring files..."
      cd / && $BORG_CMD extract --progress ::$ARCHIVE var/lib/immich var/backup/immich-db

      echo "Restoring database..."
      sudo -u postgres ${config.services.postgresql.package}/bin/pg_restore -d immich --clean ${backupDir}/immich.dump

      echo "Starting Immich..."
      systemctl start immich-server

      echo "Restore complete!"
    '')
  ];
  # Allow HTTPS on VPN interface (nginx proxies to Immich for both web and mobile)
  networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [httpsPort];

  # Prometheus exporters for Immich dependencies
  services.prometheus.exporters = {
    postgres = {
      enable = true;
      port = postgresMetricsPort;
      listenAddress = "127.0.0.1";
      openFirewall = false;
      runAsLocalSuperUser = true;
    };

    redis = {
      enable = true;
      port = redisMetricsPort;
      listenAddress = "127.0.0.1";
      openFirewall = false;
      extraFlags = ["--redis.addr=unix:///run/redis-immich/redis.sock"];
    };

    nginx = {
      enable = true;
      port = nginxMetricsPort;
      listenAddress = "127.0.0.1";
      openFirewall = false;
      scrapeUri = "http://127.0.0.1/nginx_status";
    };
  };

  # Enable nginx status page for prometheus exporter
  services.nginx.statusPage = true;

  # Grant redis exporter access to redis socket
  users.users.redis-exporter = {
    isSystemUser = true;
    group = "redis-exporter";
    extraGroups = ["redis-immich"];
  };

  users.groups.redis-exporter = {};

  # NVMe data disk - TPM encrypted, not touched during deployment
  boot.initrd.luks.devices."immich-data" = {
    device = luksDevice;
    allowDiscards = true;
  };

  # Mount NVMe to /mnt/immich-data
  fileSystems."/mnt/immich-data" = {
    device = "/dev/mapper/immich-data";
    fsType = "ext4";
    options = ["defaults"];
  };

  # Bind mount immich data
  fileSystems."/var/lib/immich" = {
    device = "/mnt/immich-data/immich";
    fsType = "none";
    options = ["bind" "x-systemd.requires=mnt-immich\\x2ddata.mount"];
  };

  # Bind mount borg repos
  fileSystems."/var/lib/borg-repos" = {
    device = "/mnt/immich-data/borg-repos";
    fsType = "none";
    options = ["bind" "x-systemd.requires=mnt-immich\\x2ddata.mount"];
  };

  services.immich = {
    enable = true;
    # Listen on 127.0.0.1 only, accessed via nginx proxy
    host = "127.0.0.1";
    port = services.immich.port;
    # Media stored on dedicated NVMe disk at /var/lib/immich (default)
    environment = {
      PUBLIC_IMMICH_SERVER_URL = "https://share.${domain}";
      # Enable Prometheus metrics on 127.0.0.1
      IMMICH_TELEMETRY_INCLUDE = "all";
      IMMICH_API_METRICS_PORT = toString immichApiMetricsPort;
      IMMICH_MICROSERVICES_METRICS_PORT = toString immichMicroservicesMetricsPort;
    };
  };

  # Ensure required directory structure exists on the data disk
  systemd.tmpfiles.rules = [
    # Base directories on mount point
    "d /mnt/immich-data/immich 0755 immich immich -"
    "d /mnt/immich-data/borg-repos 0755 root root -"
    "d /mnt/immich-data/borg-repos/immich 0700 root root -"
    # Immich subdirectories
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
  services.borgbackup.jobs = let
    commonConfig = {
      paths = [
        "/var/lib/immich"
        backupDir
      ];
      exclude = [
        "/var/lib/immich/thumbs"
        "/var/lib/immich/encoded-video"
      ];
      compression = "auto,zstd";
      startAt = "daily";
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
  in {
    immich-remote =
      commonConfig
      // {
        repo = "ssh://borg@vpsfree.nb.krejci.io/var/lib/borg-repos/immich";
        startAt = "02:00";
        encryption = {
          mode = "repokey-blake2";
          passCommand = "cat /root/secrets/borg-passphrase-remote";
        };
        environment = {
          BORG_RSH = "ssh -i /root/.ssh/borg-backup-key";
        };
      };

    immich-local =
      commonConfig
      // {
        repo = "/var/lib/borg-repos/immich";
        startAt = "03:00";
        encryption = {
          mode = "repokey-blake2";
          passCommand = "cat /root/secrets/borg-passphrase-local";
        };
      };
  };

  # Wait for services interface before binding
  systemd.services.nginx.after = ["sys-subsystem-net-devices-services.device"];

  # Nginx reverse proxy - accessible via immich.<domain>
  services.nginx = {
    enable = true;
    virtualHosts.${immichDomain} = {
      listenAddresses = [host.services.immich.ip];
      # Enable HTTPS with Let's Encrypt wildcard certificate
      forceSSL = true;
      useACMEHost = "${domain}";
      # Allow large file uploads for photos and videos
      extraConfig = ''
        client_max_body_size 1G;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString services.immich.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
    # Immich and infrastructure metrics via unified metrics proxy
    virtualHosts."metrics".locations = {
      "/metrics/immich".proxyPass = "http://127.0.0.1:${toString immichApiMetricsPort}/metrics";
      "/metrics/immich-microservices".proxyPass = "http://127.0.0.1:${toString immichMicroservicesMetricsPort}/metrics";
      "/metrics/postgres".proxyPass = "http://127.0.0.1:${toString postgresMetricsPort}/metrics";
      "/metrics/redis".proxyPass = "http://127.0.0.1:${toString redisMetricsPort}/metrics";
      "/metrics/nginx".proxyPass = "http://127.0.0.1:${toString nginxMetricsPort}/metrics";
    };
    };
  };
}

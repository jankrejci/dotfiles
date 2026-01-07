# Helper function for borg backup configuration
#
# This is a helper function instead of a central NixOS module because the module
# system causes infinite recursion when a module both defines and iterates over
# config options. A central backup module that uses mapAttrsToList on
# config.homelab.backup.jobs forces evaluation of all module contributions, but
# those contributions are inside mkIf cfg.enable blocks that defer evaluation.
# Each service module calls this function directly, avoiding the cycle.
#
# Usage in service modules:
#   let
#     backupConfig = import ../lib/backup.nix { inherit lib pkgs; };
#   in {
#     config = lib.mkMerge [
#       (backupConfig.mkBorgBackup {
#         name = "memos";
#         hostName = config.homelab.host.hostName;
#         paths = ["/var/lib/memos"];
#         excludes = ["/var/lib/memos/thumbnails"];
#         database = "memos";
#         service = "memos";
#         hour = 2;
#       })
#       { /* other config */ }
#     ];
#   }
{
  lib,
  pkgs,
}: let
  inherit (lib) optional optionalAttrs optionalString;
in {
  # Generate borg backup config for a service
  mkBorgBackup = {
    name,
    hostName,
    paths,
    excludes ? [],
    database ? null,
    service,
    hour ? 2,
  }: let
    dbBackupDir = "/var/backup/${name}-db";
    hourStr = lib.fixedWidthString 2 "0" (toString hour);

    commonBorgConfig = {
      inherit paths;
      exclude = excludes;
      compression = "auto,zstd";
      startAt = "daily";
      persistentTimer = true;
      prune.keep = {
        daily = 7;
        weekly = 4;
        monthly = 6;
      };
    };

    capitalizedName = let
      first = lib.toUpper (builtins.substring 0 1 name);
      rest = builtins.substring 1 (-1) name;
    in
      first + rest;

    restoreScript = pkgs.writeShellScriptBin "restore-${name}-backup" ''
      set -euo pipefail

      if [ $# -lt 2 ]; then
        echo "Usage: restore-${name}-backup <remote|local> ARCHIVE_NAME"
        echo ""
        echo "Available remote backups:"
        borg-job-${name}-remote list
        echo ""
        echo "Available local backups:"
        borg-job-${name}-local list
        exit 1
      fi

      readonly SOURCE="$1"
      readonly ARCHIVE="$2"

      case "$SOURCE" in
        remote) BORG_CMD="borg-job-${name}-remote" ;;
        local) BORG_CMD="borg-job-${name}-local" ;;
        *) echo "Error: Source must be 'remote' or 'local'"; exit 1 ;;
      esac

      echo "WARNING: This will restore ${name} data from $SOURCE backup: $ARCHIVE"
      echo "Current data will be overwritten!"
      read -p "Continue? [y/N] " -r
      [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

      echo "Stopping ${service}..."
      systemctl stop ${service}

      echo "Extracting backup..."
      cd /
      $BORG_CMD extract --strip-components 0 "::$ARCHIVE"

      ${optionalString (database != null) ''
        echo "Restoring database..."
        sudo -u postgres dropdb ${database} || true
        sudo -u postgres createdb -O ${database} ${database}
        sudo -u postgres pg_restore -d ${database} ${dbBackupDir}/${name}.dump
      ''}

      echo "Starting ${service}..."
      systemctl start ${service}

      echo "Restore complete!"
    '';
  in {
    services.borgbackup.jobs = {
      "${name}-remote" =
        commonBorgConfig
        // {
          repo = "ssh://borg@vpsfree.nb.krejci.io/var/lib/borg-repos/${name}";
          startAt = "${hourStr}:00";
          encryption = {
            mode = "repokey-blake2";
            passCommand = "cat /root/secrets/borg-passphrase-remote";
          };
          environment.BORG_RSH = "ssh -i /root/.ssh/borg-backup-key";
        }
        // optionalAttrs (database != null) {
          paths = paths ++ [dbBackupDir];
          preHook = "systemctl start ${name}-db-dump.service";
        };

      "${name}-local" =
        commonBorgConfig
        // {
          repo = "/var/lib/borg-repos/${name}";
          startAt = "${hourStr}:30";
          encryption = {
            mode = "repokey-blake2";
            passCommand = "cat /root/secrets/borg-passphrase-local";
          };
        }
        // optionalAttrs (database != null) {
          paths = paths ++ [dbBackupDir];
          preHook = "systemctl start ${name}-db-dump.service";
        };
    };

    systemd.services = optionalAttrs (database != null) {
      "${name}-db-dump" = {
        description = "Dump ${name} PostgreSQL database";
        path = [pkgs.postgresql];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          ExecStart = "pg_dump -Fc -f ${dbBackupDir}/${name}.dump ${database}";
        };
      };
    };

    systemd.tmpfiles.rules =
      optional (database != null)
      "d ${dbBackupDir} 0700 postgres postgres -";

    environment.systemPackages = [
      pkgs.borgbackup
      restoreScript
    ];

    homelab.alerts."${name}-backup" = [
      {
        alert = "${capitalizedName}LocalBackupFailed";
        expr = ''node_systemd_unit_state{name="borgbackup-job-${name}-local.service",state="failed",host="${hostName}"} > 0'';
        labels = {
          severity = "critical";
          host = hostName;
          type = "service";
        };
        annotations.summary = "${capitalizedName} local backup failed";
      }
      {
        alert = "${capitalizedName}RemoteBackupFailed";
        expr = ''node_systemd_unit_state{name="borgbackup-job-${name}-remote.service",state="failed",host="${hostName}"} > 0'';
        labels = {
          severity = "critical";
          host = hostName;
          type = "service";
        };
        annotations.summary = "${capitalizedName} remote backup failed";
      }
    ];
  };
}

# Helper function for borg backup configuration
#
# Why native services.borgbackup instead of borgmatic:
#   Borgmatic adds a YAML config layer that introduces bugs in the NixOS module:
#   - pg_dump PATH issues: github.com/NixOS/nixpkgs/issues/329602
#   - PostgreSQL format bug: github.com/NixOS/nixpkgs/issues/412113
#   - Empty database crash: github.com/NixOS/nixpkgs/issues/437241
#   The native module gives direct control over hooks and avoids these issues.
#
# Why a helper function instead of a NixOS module:
#   The module system causes infinite recursion when a module both defines and
#   iterates over config options. A central backup module using mapAttrsToList
#   on config.homelab.backup.jobs forces evaluation of all contributions, but
#   those are inside mkIf cfg.enable blocks that defer evaluation. Each service
#   module calls this function directly, avoiding the cycle.
#
# Architecture:
#   - Two backup targets per service: local and remote
#   - Local: /var/lib/borg-repos on the same machine, runs at HH:30
#   - Remote: vpsfree server via SSH, runs at HH:00
#   - Database dumps run as preHook before backup starts
#   - Success timestamps written to textfile collector for Prometheus metrics
#
# Monitoring:
#   - Prometheus alerts on failed systemd unit state
#   - Grafana dashboard shows hours since last successful backup
#   - Metrics exported via node_exporter textfile collector
#
# Usage:
#   let
#     backup = import ../lib/backup.nix { inherit lib pkgs; };
#   in {
#     config = lib.mkMerge [
#       (backup.mkBorgBackup {
#         name = "memos";
#         hostName = config.homelab.host.hostName;
#         paths = ["/var/lib/memos"];
#         excludes = ["/var/lib/memos/thumbnails"];
#         database = "memos";  # optional: PostgreSQL database to dump
#         service = "memos";   # systemd service to stop during restore
#         hour = 2;            # hour to run backups (remote at :00, local at :30)
#       })
#       { /* other config */ }
#     ];
#   }
{
  lib,
  pkgs,
}: let
  inherit (lib) optional optionalAttrs optionalString;

  # Backup targets with their specific configuration
  targets = {
    remote = {
      repo = name: "ssh://borg@vpsfree.nb.krejci.io/var/lib/borg-repos/${name}";
      timeOffset = ":00";
      passphrasePath = "/root/secrets/borg-passphrase-remote";
      extraEnv = {BORG_RSH = "ssh -i /root/.ssh/borg-backup-key";};
    };
    local = {
      repo = name: "/var/lib/borg-repos/${name}";
      timeOffset = ":30";
      passphrasePath = "/root/secrets/borg-passphrase-local";
      extraEnv = {};
    };
  };
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
    metricsDir = "/var/lib/prometheus-node-exporter";

    # Write success timestamp for Prometheus textfile collector
    mkPostHook = target: ''
      echo "borg_backup_last_success_timestamp{name=\"${name}\",target=\"${target}\"} $(date +%s)" > ${metricsDir}/borg-${name}-${target}.prom.tmp
      mv ${metricsDir}/borg-${name}-${target}.prom.tmp ${metricsDir}/borg-${name}-${target}.prom
    '';

    # Generate borg job config for a target
    mkBorgJob = target: let
      cfg = targets.${target};
    in
      {
        inherit paths;
        exclude = excludes;
        compression = "auto,zstd";
        persistentTimer = true;
        prune.keep = {
          daily = 7;
          weekly = 4;
          monthly = 6;
        };
        readWritePaths = [metricsDir];
        repo = cfg.repo name;
        startAt = "${hourStr}${cfg.timeOffset}";
        encryption = {
          mode = "repokey-blake2";
          passCommand = "cat ${cfg.passphrasePath}";
        };
        environment = cfg.extraEnv;
        postHook = mkPostHook target;
      }
      // optionalAttrs (database != null) {
        paths = paths ++ [dbBackupDir];
        preHook = "systemctl start ${name}-db-dump.service";
      };

    # Generate alert for a target
    mkAlert = target: {
      alert = "${name}-${target}-backup-failed";
      expr = ''node_systemd_unit_state{name="borgbackup-job-${name}-${target}.service",state="failed",host="${hostName}"} > 0'';
      labels = {
        severity = "critical";
        host = hostName;
        type = "service";
      };
      annotations.summary = "${name} ${target} backup failed";
    };

    # Generate health check for a target
    mkHealthCheck = target: {
      name = "Backup ${name}-${target}";
      script = pkgs.writeShellApplication {
        name = "health-check-backup-${name}-${target}";
        runtimeInputs = [pkgs.systemd pkgs.coreutils];
        text = ''
          systemctl is-enabled --quiet borgbackup-job-${name}-${target}.timer || {
            echo "Backup timer disabled"
            exit 1
          }

          result=$(systemctl show borgbackup-job-${name}-${target}.service -p Result --value)
          if [ "$result" != "success" ] && [ -n "$result" ]; then
            echo "Backup failed: $result"
            exit 1
          fi

          last_run=$(systemctl show borgbackup-job-${name}-${target}.service -p ActiveEnterTimestamp --value)
          [ -z "$last_run" ] || [ "$last_run" = "n/a" ] && exit 0

          last_run_epoch=$(date -d "$last_run" +%s 2>/dev/null || echo "0")
          [ "$last_run_epoch" = "0" ] && exit 0

          current_epoch=$(date +%s)
          age_hours=$(( (current_epoch - last_run_epoch) / 3600 ))
          if [ "$age_hours" -gt 48 ]; then
            echo "Backup stale ($age_hours hours)"
            exit 1
          fi
        '';
      };
      timeout = 15;
    };

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
        sudo -u postgres ${pkgs.postgresql}/bin/dropdb ${database} || true
        sudo -u postgres ${pkgs.postgresql}/bin/createdb -O ${database} ${database}
        sudo -u postgres ${pkgs.postgresql}/bin/pg_restore -d ${database} ${dbBackupDir}/${name}.dump
      ''}

      echo "Starting ${service}..."
      systemctl start ${service}

      echo "Restore complete!"
    '';

    targetNames = lib.attrNames targets;
  in {
    services.borgbackup.jobs =
      lib.genAttrs
      (map (t: "${name}-${t}") targetNames)
      (jobName: mkBorgJob (lib.removePrefix "${name}-" jobName));

    systemd.services = optionalAttrs (database != null) {
      "${name}-db-dump" = {
        description = "Dump ${name} PostgreSQL database";
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          ExecStart = "${pkgs.postgresql}/bin/pg_dump -Fc -f ${dbBackupDir}/${name}.dump ${database}";
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

    homelab.alerts."${name}-backup" = map mkAlert targetNames;
    homelab.healthChecks = map mkHealthCheck targetNames;
  };
}

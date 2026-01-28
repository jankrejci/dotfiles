# Central backup module
#
# This module collects backup jobs from the current host via homelab.backup.jobs
# and generates all necessary configuration:
# - borgbackup jobs for local and remote targets
# - database dump services for PostgreSQL backups
# - restore scripts for disaster recovery
# - Prometheus alerts for backup failures
# - health checks for staleness monitoring
#
# Why native services.borgbackup instead of borgmatic:
#   Borgmatic adds a YAML config layer that introduces bugs in the NixOS module:
#   - pg_dump PATH issues: github.com/NixOS/nixpkgs/issues/329602
#   - PostgreSQL format bug: github.com/NixOS/nixpkgs/issues/412113
#   - Empty database crash: github.com/NixOS/nixpkgs/issues/437241
#   The native module gives direct control over hooks and avoids these issues.
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
# Usage in service modules:
#   homelab.backup.jobs = [{
#     name = "memos";
#     paths = ["/var/lib/memos"];
#     excludes = ["/var/lib/memos/thumbnails"];
#     database = "memos";
#     service = "memos";
#     hour = 2;
#   }];
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.backup;
  hostName = config.homelab.host.hostName;
  jobs = cfg.jobs;
  metricsDir = "/var/lib/prometheus-node-exporter";

  # Generate configuration for a single backup job
  mkJobConfig = job: let
    inherit (job) name paths excludes database service hour;
    dbBackupDir = "/var/backup/${name}-db";
    hourStr = lib.fixedWidthString 2 "0" (toString hour);

    # Write success timestamp for Prometheus textfile collector
    mkPostHook = target: ''
      echo "borg_backup_last_success_timestamp{name=\"${name}\",target=\"${target}\"} $(date +%s)" > ${metricsDir}/borg-${name}-${target}.prom.tmp
      mv ${metricsDir}/borg-${name}-${target}.prom.tmp ${metricsDir}/borg-${name}-${target}.prom
    '';

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
      # Allow writing metrics to textfile collector directory
      readWritePaths = [metricsDir];
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

      ${lib.optionalString (database != null) ''
        echo "Restoring database..."
        sudo -u postgres ${pkgs.postgresql}/bin/dropdb ${database} || true
        sudo -u postgres ${pkgs.postgresql}/bin/createdb -O ${database} ${database}
        sudo -u postgres ${pkgs.postgresql}/bin/pg_restore -d ${database} ${dbBackupDir}/${name}.dump
      ''}

      echo "Starting ${service}..."
      systemctl start ${service}

      echo "Restore complete!"
    '';
  in {
    # Remote borgbackup job
    borgJobsRemote = lib.optionalAttrs cfg.remote.enable {
      "${name}-remote" =
        commonBorgConfig
        // {
          repo = "ssh://${cfg.remote.server}${cfg.remote.repoBase}/${name}";
          startAt = "${hourStr}:00";
          encryption = {
            mode = "repokey-blake2";
            passCommand = "cat ${remotePassphrasePath}";
          };
          environment.BORG_RSH = "ssh -i /root/.ssh/borg-backup-key";
          postHook = mkPostHook "remote";
        }
        // lib.optionalAttrs (database != null) {
          paths = paths ++ [dbBackupDir];
          preHook = "systemctl start ${name}-db-dump.service";
        };
    };

    # Local borgbackup job
    borgJobsLocal = lib.optionalAttrs cfg.local.enable {
      "${name}-local" =
        commonBorgConfig
        // {
          repo = "${cfg.local.repoBase}/${name}";
          startAt = "${hourStr}:30";
          encryption = {
            mode = "repokey-blake2";
            passCommand = "cat ${localPassphrasePath}";
          };
          postHook = mkPostHook "local";
        }
        // lib.optionalAttrs (database != null) {
          paths = paths ++ [dbBackupDir];
          preHook = "systemctl start ${name}-db-dump.service";
        };
    };

    # Database dump service
    dbDumpServices = lib.optionalAttrs (database != null) {
      "${name}-db-dump" = {
        description = "Dump ${name} PostgreSQL database";
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          # Full path required because systemd resolves ExecStart executables
          # before PATH environment is set. Bare "pg_dump" fails with ENOENT.
          ExecStart = "${pkgs.postgresql}/bin/pg_dump -Fc -f ${dbBackupDir}/${name}.dump ${database}";
        };
      };
    };

    # Tmpfiles for database dump directory
    tmpfilesRules =
      lib.optional (database != null)
      "d ${dbBackupDir} 0700 postgres postgres -";

    # Restore script package
    restoreScripts = [restoreScript];

    # Prometheus alerts for backup failures
    alerts = lib.flatten [
      (lib.optional cfg.local.enable {
        alert = "${capitalizedName}LocalBackupFailed";
        expr = ''node_systemd_unit_state{name="borgbackup-job-${name}-local.service",state="failed",host="${hostName}"} > 0'';
        labels = {
          severity = "critical";
          host = hostName;
          type = "service";
        };
        annotations.summary = "${capitalizedName} local backup failed";
      })
      (lib.optional cfg.remote.enable {
        alert = "${capitalizedName}RemoteBackupFailed";
        expr = ''node_systemd_unit_state{name="borgbackup-job-${name}-remote.service",state="failed",host="${hostName}"} > 0'';
        labels = {
          severity = "critical";
          host = hostName;
          type = "service";
        };
        annotations.summary = "${capitalizedName} remote backup failed";
      })
    ];

    # Health checks for backup staleness
    healthChecks = lib.flatten [
      (lib.optional cfg.remote.enable {
        name = "Backup ${name}-remote";
        script = pkgs.writeShellApplication {
          name = "health-check-backup-${name}-remote";
          runtimeInputs = [pkgs.systemd pkgs.coreutils];
          text = ''
            systemctl is-enabled --quiet borgbackup-job-${name}-remote.timer || {
              echo "Backup timer disabled"
              exit 1
            }

            result=$(systemctl show borgbackup-job-${name}-remote.service -p Result --value)
            if [ "$result" != "success" ] && [ -n "$result" ]; then
              echo "Backup failed: $result"
              exit 1
            fi

            last_run=$(systemctl show borgbackup-job-${name}-remote.service -p ActiveEnterTimestamp --value)
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
      })
      (lib.optional cfg.local.enable {
        name = "Backup ${name}-local";
        script = pkgs.writeShellApplication {
          name = "health-check-backup-${name}-local";
          runtimeInputs = [pkgs.systemd pkgs.coreutils];
          text = ''
            systemctl is-enabled --quiet borgbackup-job-${name}-local.timer || {
              echo "Backup timer disabled"
              exit 1
            }

            result=$(systemctl show borgbackup-job-${name}-local.service -p Result --value)
            if [ "$result" != "success" ] && [ -n "$result" ]; then
              echo "Backup failed: $result"
              exit 1
            fi

            last_run=$(systemctl show borgbackup-job-${name}-local.service -p ActiveEnterTimestamp --value)
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
      })
    ];
  };

  # Generate configs for all jobs
  allJobConfigs = map mkJobConfig jobs;

  # Merge all job configs into single attrsets
  mergeConfigs = f: lib.foldl' (acc: jc: acc // (f jc)) {} allJobConfigs;
  mergeConfigsLists = f: lib.flatten (map f allJobConfigs);

  anyBackupEnabled = cfg.remote.enable || cfg.local.enable;
  hasJobs = jobs != [];

  # Agenix secret paths for borg passphrases
  remotePassphrasePath = config.age.secrets.borg-passphrase-remote.path;
  localPassphrasePath = config.age.secrets.borg-passphrase-local.path;
in {
  config = lib.mkIf (anyBackupEnabled && hasJobs) {
    # Agenix secrets for borg passphrases
    age.secrets = lib.mkMerge [
      (lib.mkIf cfg.remote.enable {
        borg-passphrase-remote.rekeyFile = ../secrets/borg-passphrase-remote-${hostName}.age;
      })
      (lib.mkIf cfg.local.enable {
        borg-passphrase-local.rekeyFile = ../secrets/borg-passphrase-local-${hostName}.age;
      })
    ];
    services.borgbackup.jobs =
      mergeConfigs (jc: jc.borgJobsRemote)
      // mergeConfigs (jc: jc.borgJobsLocal);

    systemd.services = mergeConfigs (jc: jc.dbDumpServices);

    systemd.tmpfiles.rules = mergeConfigsLists (jc: jc.tmpfilesRules);

    environment.systemPackages =
      [pkgs.borgbackup]
      ++ mergeConfigsLists (jc: jc.restoreScripts);

    homelab.alerts =
      lib.optionalAttrs (mergeConfigsLists (jc: jc.alerts) != [])
      {"backup" = mergeConfigsLists (jc: jc.alerts);};

    homelab.healthChecks = mergeConfigsLists (jc: jc.healthChecks);
  };
}

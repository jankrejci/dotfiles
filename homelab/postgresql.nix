# Shared PostgreSQL database server
#
# - used by dex, grafana, immich, memos
# - databases created per-service via ensureDatabases
# - listens on localhost only
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.postgresql;
in {
  options.homelab.postgresql = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable PostgreSQL database";
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql.enable = true;

    # PostgreSQL prometheus exporter
    services.prometheus.exporters.postgres = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9187;
      runAsLocalSuperUser = true;
    };

    # Metrics endpoint
    services.nginx.virtualHosts."metrics".locations."/metrics/postgres".proxyPass = "http://127.0.0.1:9187/metrics";

    # Scrape target
    homelab.scrapeTargets = [
      {
        job = "postgres";
        metricsPath = "/metrics/postgres";
      }
    ];

    # Alert
    homelab.alerts.postgres = [
      {
        alert = "PostgresDown";
        expr = ''pg_up{job="postgres",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "PostgreSQL is down";
      }
    ];

    # Health check
    homelab.healthChecks = [
      {
        name = "PostgreSQL";
        script = pkgs.writeShellApplication {
          name = "health-check-postgresql";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet postgresql.service
          '';
        };
        timeout = 10;
      }
      {
        name = "PostgreSQL collation";
        script = pkgs.writeShellApplication {
          name = "health-check-postgresql-collation";
          runtimeInputs = [
            pkgs.util-linux
            config.services.postgresql.package
            pkgs.gnugrep
          ];
          # PostgreSQL records the collation version when a database is created
          # and stops vouching for text index ordering once the OS moves past
          # it, which is what a glibc bump does. Grepping the warning postgres
          # already emits on connect is more reliable than comparing versions
          # by hand, because pg_collation_actual_version returns null for the
          # default collation. Recovery is a REINDEX followed by
          # ALTER DATABASE <name> REFRESH COLLATION VERSION.
          text = ''
            databases=$(runuser -u postgres -- \
              psql -At -c "select datname from pg_database where datallowconn") || {
              echo "cannot list databases"
              exit 1
            }

            mismatched=$(printf '%s\n' "$databases" | while read -r db; do
              test -n "$db" || continue
              # Capture the output instead of piping into grep -q, which exits
              # on first match and SIGPIPEs psql under pipefail, dropping the
              # database exactly when the warning fires.
              connect_output=$(runuser -u postgres -- \
                psql -d "$db" -c "select 1" 2>&1 || true)
              grep -q "collation version mismatch" <<< "$connect_output" || continue
              printf ' %s' "$db"
            done)

            test -z "$mismatched" || {
              echo "collation version mismatch:$mismatched"
              exit 1
            }
          '';
        };
        timeout = 30;
      }
    ];
  };
}

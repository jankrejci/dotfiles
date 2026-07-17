# Loki log aggregation with Fluent Bit shipper
#
# - receives logs from systemd journal via Fluent Bit
# - 30-day retention with auto-delete
# - Grafana datasource auto-provisioned
# - single-tenant mode for simplicity
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.loki;
  lokiDataDir = "/var/lib/loki";
in {
  options.homelab.loki = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Loki log aggregation";
    };

    port = {
      loki = lib.mkOption {
        type = lib.types.port;
        description = "Port for Loki server";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Loki: log aggregation system (like Prometheus but for logs)
    # Receives logs from Fluent Bit and stores them for querying via Grafana
    services.loki = {
      enable = true;
      configuration = {
        # Single-tenant mode (no authentication between components)
        auth_enabled = false;

        server = {
          http_listen_port = cfg.port.loki;
          # 127.0.0.1 only - defense in depth, accessed via Grafana
          http_listen_address = "127.0.0.1";
        };

        common = {
          path_prefix = lokiDataDir;
          # Single instance, no replication needed
          replication_factor = 1;
          # In-memory ring for single-node deployment (no etcd/consul needed)
          ring.kvstore.store = "inmemory";
          ring.instance_addr = "127.0.0.1";
        };

        # Schema defines how logs are indexed and stored
        # v13 with tsdb is the current recommended schema
        schema_config.configs = [
          {
            from = "2024-01-01";
            store = "tsdb"; # Time-series database for index
            object_store = "filesystem"; # Local disk storage
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h"; # New index file every 24h
            };
          }
        ];

        # Store log chunks on local filesystem
        storage_config.filesystem.directory = "${lokiDataDir}/chunks";

        limits_config = {
          # Auto-delete logs older than 30 days
          retention_period = "30d";
          # Rate limits for ingestion - high for initial backfill
          ingestion_rate_mb = 16;
          ingestion_burst_size_mb = 32;
          # Allow many streams - systemd creates thousands of unique units
          # (transient units like systemd-coredump@... have unique IDs)
          max_global_streams_per_user = 50000;
        };

        # Compactor handles retention enforcement and index compaction
        compactor = {
          working_directory = "${lokiDataDir}/compactor";
          retention_enabled = true;
          # Wait 2h before actually deleting (allows for recovery)
          retention_delete_delay = "2h";
          delete_request_store = "filesystem";
        };
      };
    };

    # Ensure state directory exists, required for systemd namespace setup
    systemd.tmpfiles.rules = [
      "d /var/lib/loki 0700 loki loki -"
    ];

    # Fluent Bit: agent that ships journal logs to Loki.
    # Replaces Promtail, which was removed upstream in NixOS 26.05.
    services.fluent-bit = {
      enable = true;
      settings = {
        service = {
          flush = 1;
          log_level = "info";
        };
        pipeline = {
          inputs = [
            {
              name = "systemd";
              tag = "journal";
              # Resume from last read on restart; DB path is under StateDirectory.
              # On first deploy or after a state-dir wipe there is no cursor yet,
              # so this ships only new journal entries. Promtail's former
              # max_age = "48h" backfilled recent history on startup; Fluent
              # Bit's systemd input has no clean equivalent, so a first deploy
              # or state wipe ships no historical journal.
              read_from_tail = "on";
              db = "/var/lib/fluent-bit/systemd.db";
            }
          ];
          filters = [
            {
              name = "modify";
              match = "journal";
              # Rename raw journal fields to match previous Promtail labels so
              # existing Grafana queries keep working. Note: level now carries
              # the raw journal PRIORITY, a digit 0-7 as a string, instead of
              # the keyword form "error", "warning", etc. that Promtail synthesised from
              # __journal_priority_keyword. In-repo dashboards and alerts do
              # not filter on the keyword form, but external LogQL queries of
              # the shape {level="error"} will return no results.
              rename = [
                "_SYSTEMD_UNIT unit"
                "PRIORITY level"
                "_HOSTNAME hostname"
              ];
            }
          ];
          outputs = [
            {
              name = "loki";
              match = "*";
              host = "127.0.0.1";
              port = cfg.port.loki;
              labels = "job=systemd-journal,host=${config.networking.hostName}";
              label_keys = "$unit,$level,$hostname";
            }
          ];
        };
      };
    };

    # Persistent DB for the journal read position. DynamicUser requires
    # StateDirectory to get a writable directory.
    systemd.services.fluent-bit.serviceConfig.StateDirectory = "fluent-bit";

    # Add Loki datasource to Grafana for log exploration
    services.grafana.provision.datasources.settings.datasources = [
      {
        name = "Loki";
        type = "loki";
        access = "proxy";
        url = "http://127.0.0.1:${toString cfg.port.loki}";
        # Fixed UID for dashboard references (see CLAUDE.md)
        uid = "loki";
        jsonData = {
          maxLines = 1000;
        };
      }
    ];

    # Alert rules for loki and fluent-bit
    homelab.alerts.loki = [
      {
        alert = "LokiDown";
        expr = ''node_systemd_unit_state{name="loki.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Loki service is not active";
      }
      {
        alert = "FluentBitDown";
        expr = ''node_systemd_unit_state{name="fluent-bit.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Fluent Bit log shipper is not active";
      }
    ];

    # Health checks
    homelab.healthChecks = [
      {
        name = "Loki";
        script = pkgs.writeShellApplication {
          name = "health-check-loki";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet loki.service
          '';
        };
        timeout = 10;
      }
      {
        name = "Fluent Bit";
        script = pkgs.writeShellApplication {
          name = "health-check-fluent-bit";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet fluent-bit.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

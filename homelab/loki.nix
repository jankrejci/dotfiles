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

    port = lib.mkOption {
      type = lib.types.port;
      default = 3100;
      description = "Port for Loki server";
    };

    promtailPort = lib.mkOption {
      type = lib.types.port;
      default = 9080;
      description = "Port for Promtail agent";
    };
  };

  config = lib.mkIf cfg.enable {
    # Loki: log aggregation system (like Prometheus but for logs)
    # Receives logs from Promtail and stores them for querying via Grafana
    services.loki = {
      enable = true;
      configuration = {
        # Single-tenant mode (no authentication between components)
        auth_enabled = false;

        server = {
          http_listen_port = cfg.port;
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

    # Ensure state directories exist (required for systemd namespace setup)
    systemd.tmpfiles.rules = [
      "d /var/lib/loki 0700 loki loki -"
      "d /var/lib/promtail 0700 promtail promtail -"
    ];

    # Promtail: agent that ships logs to Loki
    # Reads from systemd journal and forwards to Loki
    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = cfg.promtailPort;
          http_listen_address = "127.0.0.1";
          # Disable gRPC (not needed, conflicts with loki's default 9095)
          grpc_listen_port = 0;
        };

        # Track which journal entries have been sent (survives restarts)
        positions.filename = "/var/lib/promtail/positions.yaml";

        # Where to send logs
        clients = [
          {url = "http://127.0.0.1:${toString cfg.port}/loki/api/v1/push";}
        ];

        scrape_configs = [
          {
            job_name = "journal";
            journal = {
              # Ship logs from last 48h on startup (covers weekend gaps)
              max_age = "48h";
              labels = {
                job = "systemd-journal";
                host = config.networking.hostName;
              };
            };
            # Extract useful labels from journal metadata
            relabel_configs = [
              {
                # systemd unit name (e.g., nginx.service, immich-server.service)
                source_labels = ["__journal__systemd_unit"];
                target_label = "unit";
              }
              {
                # Log level (emerg, alert, crit, err, warning, notice, info, debug)
                source_labels = ["__journal_priority_keyword"];
                target_label = "level";
              }
              {
                source_labels = ["__journal__hostname"];
                target_label = "hostname";
              }
            ];
          }
        ];
      };
    };

    # Add Loki datasource to Grafana for log exploration
    services.grafana.provision.datasources.settings.datasources = [
      {
        name = "Loki";
        type = "loki";
        access = "proxy";
        url = "http://127.0.0.1:${toString cfg.port}";
        # Fixed UID for dashboard references (see CLAUDE.md)
        uid = "loki";
        jsonData = {
          maxLines = 1000;
        };
      }
    ];
  };
}

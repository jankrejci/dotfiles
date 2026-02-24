# Memos note-taking service
#
# - self-hosted notes with markdown support
# - PostgreSQL backend with borg backup
# - Dex SSO authentication
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.memos;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  memosDomain = "${cfg.subdomain}.${domain}";
in {
  options.homelab.memos = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Memos note-taking service";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      description = "Port for memos server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "memos";
      description = "Subdomain for memos";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Register IP for services dummy interface
      homelab.serviceIPs = [cfg.ip];
      networking.hosts.${cfg.ip} = [memosDomain];

      # Firewall: allow HTTPS on VPN interface
      networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
        services.https.port
      ];

      # Create memos database in PostgreSQL, reuses existing server from immich
      services.postgresql = {
        ensureDatabases = ["memos"];
        ensureUsers = [
          {
            name = "memos";
            ensureDBOwnership = true;
          }
        ];
      };

      # Memos service with PostgreSQL backend
      # Override to 0.26.1 for moe-memos Android client compatibility
      services.memos = {
        enable = true;
        package = pkgs.unstable.memos;
        settings = {
          MEMOS_ADDR = "127.0.0.1";
          MEMOS_PORT = toString cfg.port;
          MEMOS_DRIVER = "postgres";
          MEMOS_DSN = "postgresql:///memos?host=/run/postgresql";
          # 0.26.x requires explicit data dir, no longer has a built-in default
          MEMOS_DATA = "/var/lib/memos";
        };
      };

      # Ensure memos starts after PostgreSQL
      systemd.services.memos.after = ["postgresql.service"];
      systemd.services.memos.requires = ["postgresql.service"];

      # Nginx reverse proxy
      services.nginx.virtualHosts.${memosDomain} = {
        listenAddresses = [cfg.ip];
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    }

    # Alert and health check
    {
      homelab.dashboardEntries = [
        {
          name = "Memos";
          url = "https://${memosDomain}";
          icon = ../assets/dashboard-icons/memos.svg;
        }
      ];

      homelab.alerts.memos = [
        {
          alert = "MemosDown";
          expr = ''node_systemd_unit_state{name="memos.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
          labels = {
            severity = "warning";
            host = config.homelab.host.hostName;
            type = "service";
          };
          annotations.summary = "Memos note-taking service is down";
        }
      ];

      homelab.healthChecks = [
        {
          name = "Memos";
          script = pkgs.writeShellApplication {
            name = "health-check-memos";
            runtimeInputs = [pkgs.systemd];
            text = ''
              systemctl is-active --quiet memos.service
            '';
          };
          timeout = 10;
        }
      ];
    }

    # Register backup job for borg backup with database dump
    {
      homelab.backup.jobs = [
        {
          name = "memos";
          paths = ["/var/lib/memos"];
          excludes = ["/var/lib/memos/thumbnails"];
          database = "memos";
          service = "memos";
          hour = 2;
        }
      ];
    }
  ]);
}

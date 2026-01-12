# Memos note-taking service with homelab enable flag
{
  config,
  lib,
  pkgs,
  backup,
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
      default = 5230;
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
      # Use unstable memos to fix PostgreSQL reactions bug in 0.25.2
      services.memos = {
        enable = true;
        package = pkgs.unstable.memos;
        settings = {
          MEMOS_ADDR = "127.0.0.1";
          MEMOS_PORT = toString cfg.port;
          MEMOS_DRIVER = "postgres";
          MEMOS_DSN = "postgresql:///memos?host=/run/postgresql";
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

    # Health check
    {
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

    # Borg backup with database dump
    (backup.mkBorgBackup {
      name = "memos";
      hostName = config.homelab.host.hostName;
      paths = ["/var/lib/memos"];
      excludes = ["/var/lib/memos/thumbnails"];
      database = "memos";
      service = "memos";
      hour = 2;
    })
  ]);
}

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
  hostName = config.homelab.host.hostName;
  domain = global.domain;
  memosDomain = "${cfg.subdomain}.${domain}";

  # Secret paths
  secretsDir = "/var/lib/memos/secrets";
  dexClientSecretPath = "${secretsDir}/dex-client";

  # Handler for writing dex client secret to memos secrets directory.
  # Note: Memos reads OAuth secret from web UI, not from file. The admin
  # must copy the secret from this file into Settings -> SSO.
  dexSecretHandler = pkgs.writeShellApplication {
    name = "memos-dex-handler";
    runtimeInputs = [pkgs.systemd];
    text = ''
      install -d -m 700 -o memos -g memos ${secretsDir}
      install -m 600 -o memos -g memos /dev/stdin ${dexClientSecretPath}
      systemctl restart memos
    '';
  };
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
      assertions = [
        {
          assertion = config.homelab.postgresql.enable;
          message = "homelab.memos requires homelab.postgresql.enable = true";
        }
        {
          assertion = config.homelab.dex.enable;
          message = "homelab.memos requires homelab.dex.enable = true for OAuth";
        }
      ];

      # Declare dex client secret for OAuth authentication.
      # Memos does not read from file - admin must copy the secret from
      # /var/lib/memos/secrets/dex-client into the Memos web UI.
      homelab.secrets.memos-dex = {
        generate = "token";
        handler = dexSecretHandler;
        username = "memos-${hostName}";
        register = "dex";
      };

      # Register with Dex for OAuth authentication
      homelab.dex.clients = [
        {
          id = "memos-${hostName}";
          name = "Memos";
          redirectURIs = ["https://memos.${domain}/auth/callback"];
        }
      ];

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
      hostName = hostName;
      paths = ["/var/lib/memos"];
      excludes = ["/var/lib/memos/thumbnails"];
      database = "memos";
      service = "memos";
      hour = 2;
    })
  ]);
}

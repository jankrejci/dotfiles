# Vaultwarden password manager
#
# - Bitwarden-compatible server with PostgreSQL backend
# - VPN-only access, clients cache vault locally for offline use
# - Admin panel protected by ADMIN_TOKEN in agenix secret
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.vaultwarden;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  vaultDomain = "${cfg.subdomain}.${domain}";
in {
  options.homelab.vaultwarden = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Vaultwarden password manager";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      description = "Port for vaultwarden server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "vault";
      description = "Subdomain for vaultwarden";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Register IP for services dummy interface
      homelab.serviceIPs = [cfg.ip];
      networking.hosts.${cfg.ip} = [vaultDomain];

      # Firewall: allow HTTPS on VPN interface
      networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
        services.https.port
      ];

      # Create vaultwarden database in PostgreSQL
      services.postgresql = {
        ensureDatabases = ["vaultwarden"];
        ensureUsers = [
          {
            name = "vaultwarden";
            ensureDBOwnership = true;
          }
        ];
      };

      # Vaultwarden service with PostgreSQL backend
      services.vaultwarden = {
        enable = true;
        dbBackend = "postgresql";
        config = {
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = cfg.port;
          DOMAIN = "https://${vaultDomain}";
          DATABASE_URL = "postgresql:///vaultwarden?host=/run/postgresql";

          # Security: disable public signups and invitations
          SIGNUPS_ALLOWED = false;
          INVITATIONS_ALLOWED = false;
          SHOW_PASSWORD_HINT = false;

          # Emergency access: allow trusted users to request vault access
          EMERGENCY_ACCESS_ALLOWED = true;

          # Rate limiting: prevent brute force attacks
          LOGIN_RATELIMIT_SECONDS = 60;
          LOGIN_RATELIMIT_MAX_BURST = 10;
          ADMIN_RATELIMIT_SECONDS = 300;
          ADMIN_RATELIMIT_MAX_BURST = 3;

          # Reverse proxy: trust X-Real-IP header for rate limiting
          IP_HEADER = "X-Real-IP";
        };
        # Contains: ADMIN_TOKEN, SSO_*, SMTP_*
        environmentFile = config.age.secrets.vaultwarden-env.path;
      };

      # Ensure vaultwarden starts after PostgreSQL
      systemd.services.vaultwarden.after = ["postgresql.service"];
      systemd.services.vaultwarden.requires = ["postgresql.service"];

      # Agenix secret for admin token
      age.secrets.vaultwarden-env = {
        rekeyFile = ../secrets/vaultwarden-env.age;
      };

      # Nginx reverse proxy with websocket support for live sync
      services.nginx.virtualHosts.${vaultDomain} = {
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
          name = "Vaultwarden";
          url = "https://${vaultDomain}";
          icon = ../assets/dashboard-icons/vaultwarden.svg;
        }
      ];

      homelab.alerts.vaultwarden = [
        {
          alert = "VaultwardenDown";
          expr = ''node_systemd_unit_state{name="vaultwarden.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
          labels = {
            severity = "warning";
            host = config.homelab.host.hostName;
            type = "service";
          };
          annotations.summary = "Vaultwarden password manager is down";
        }
      ];

      homelab.healthChecks = [
        {
          name = "Vaultwarden";
          script = pkgs.writeShellApplication {
            name = "health-check-vaultwarden";
            runtimeInputs = [pkgs.systemd];
            text = ''
              systemctl is-active --quiet vaultwarden.service
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
          name = "vaultwarden";
          paths = ["/var/lib/vaultwarden"];
          database = "vaultwarden";
          service = "vaultwarden";
          hour = 3;
        }
      ];
    }
  ]);
}

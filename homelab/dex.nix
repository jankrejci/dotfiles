# Dex OIDC identity broker
#
# SSO architecture: Services authenticate through Dex instead of directly to
# Google. This gives central control: one Google OAuth app, one login for all
# services, disable a user once to revoke access everywhere.
#
# Flow: User clicks login -> Service redirects to Dex -> Dex shows "Sign in
# with Google" or local password form -> User authenticates -> Dex returns
# identity token to service -> User logged in.
#
# Why Dex over alternatives:
# - Authentik: 700MB+ RAM, memory leaks, breaking upgrades, multiple CVEs
# - Keycloak: 1GB+ RAM, overkill for homelab
# - Zitadel: Good but NixOS module has PostgreSQL bugs
# - Dex: ~100MB RAM, stable NixOS module, simple YAML config
#
# Dex is a lightweight proxy, not a user database. User management happens in
# upstream providers. If that becomes painful, migrate to Zitadel since OIDC
# is standardized and services don't care which broker they use.
#
# Local password database is enabled for fallback access when Google is down.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.dex;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  dexDomain = "${cfg.subdomain}.${domain}";
in {
  options.homelab.dex = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Dex OIDC identity broker";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = {
      dex = lib.mkOption {
        type = lib.types.port;
        description = "Port for Dex server";
      };

      metrics = lib.mkOption {
        type = lib.types.port;
        description = "Port for Dex telemetry endpoint";
      };
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "dex";
      description = "Subdomain for Dex";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.tunnel.enable;
        message = "dex requires homelab.tunnel for vpsfree SSO proxy";
      }
    ];

    # Create dex user early so agenix can chown secrets during activation.
    # The dex service module also creates this user, but that happens after
    # agenix runs, causing chown to fail.
    users.users.dex = {
      isSystemUser = true;
      group = "dex";
    };
    users.groups.dex = {};

    # Google OAuth credentials for upstream identity provider
    age.secrets.google-oauth = {
      rekeyFile = ../secrets/google-oauth.age;
      owner = "dex";
    };

    # Client secrets for downstream OAuth clients
    age.secrets.dex-grafana-secret = {
      rekeyFile = ../secrets/dex-grafana-secret.age;
      owner = "dex";
    };
    age.secrets.dex-immich-secret = {
      rekeyFile = ../secrets/dex-immich-secret.age;
      owner = "dex";
    };
    age.secrets.dex-memos-secret = {
      rekeyFile = ../secrets/dex-memos-secret.age;
      owner = "dex";
    };
    age.secrets.dex-jellyfin-secret = {
      rekeyFile = ../secrets/dex-jellyfin-secret.age;
      owner = "dex";
    };
    # Netbird client is public (SPA), no secret needed

    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [dexDomain];

    # Allow HTTPS on VPN and WG tunnel interfaces
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];
    networking.firewall.interfaces."wg0".allowedTCPPorts = [
      services.https.port
    ];

    # Create dex database in PostgreSQL
    services.postgresql = {
      ensureDatabases = ["dex"];
      ensureUsers = [
        {
          name = "dex";
          ensureDBOwnership = true;
        }
      ];
    };

    services.dex = {
      enable = true;
      settings = {
        issuer = "https://${dexDomain}";

        storage = {
          type = "postgres";
          config = {
            host = "/run/postgresql";
            database = "dex";
            user = "dex";
            ssl.mode = "disable";
          };
        };

        web = {
          http = "127.0.0.1:${toString cfg.port.dex}";
        };

        telemetry = {
          http = "127.0.0.1:${toString cfg.port.metrics}";
        };

        # Enable local password database for username/password login
        enablePasswordDB = true;

        # Local users for password authentication
        # Generate hash: htpasswd -bnBC 10 "" 'password' | tr -d ':\n'
        staticPasswords = [
          {
            email = "admin@${domain}";
            hash = "$2b$05$/lg4t/7JU4e2bQHUSTzouOBsdLfcFYVhCjuT0UvV.HbtMTOE8WcPi";
            username = "admin";
            userID = "dex-local-admin";
          }
          {
            email = "krejcijan@protonmail.com";
            hash = "$2b$10$Ysj5N2zspcRzz1l7TOfuzum.umblcUjZ2fdlIkTjdk5hk5HXbz94e";
            username = "jkr";
            userID = "dex-local-jkr";
          }
        ];

        # Upstream identity provider: Google
        # Credentials loaded from EnvironmentFile, see systemd service config below
        connectors = [
          {
            type = "google";
            id = "google";
            name = "Google";
            config = {
              clientID = "$GOOGLE_CLIENT_ID";
              clientSecret = "$GOOGLE_CLIENT_SECRET";
              redirectURI = "https://${dexDomain}/callback";
            };
          }
        ];

        # Downstream OAuth clients
        staticClients = [
          {
            id = "grafana";
            name = "Grafana";
            redirectURIs = ["https://grafana.${domain}/login/generic_oauth"];
            secretFile = config.age.secrets.dex-grafana-secret.path;
          }
          {
            id = "immich";
            name = "Immich";
            redirectURIs = [
              "https://immich.${domain}/auth/login"
              "https://immich.${domain}/user-settings"
              "https://immich.${domain}/api/oauth/mobile-redirect"
            ];
            secretFile = config.age.secrets.dex-immich-secret.path;
          }
          {
            id = "memos";
            name = "Memos";
            redirectURIs = ["https://memos.${domain}/auth/callback"];
            secretFile = config.age.secrets.dex-memos-secret.path;
          }
          {
            id = "jellyfin";
            name = "Jellyfin";
            redirectURIs = ["https://jellyfin.${domain}/sso/OID/redirect/Dex"];
            secretFile = config.age.secrets.dex-jellyfin-secret.path;
          }
          {
            id = "netbird";
            name = "Netbird";
            # Public client: dashboard is a SPA that cannot hold a secret
            public = true;
            redirectURIs = [
              "https://netbird.${domain}/#callback"
              "https://netbird.${domain}/#silent-callback"
              "http://localhost:53000"
            ];
          }
        ];
      };
    };

    # Ensure dex starts after PostgreSQL and network is online.
    # Dex fetches Google OIDC discovery at startup which needs working DNS.
    systemd.services.dex.after = ["postgresql.service" "network-online.target"];
    systemd.services.dex.requires = ["postgresql.service"];
    systemd.services.dex.wants = ["network-online.target"];
    systemd.services.dex.serviceConfig.EnvironmentFile = config.age.secrets.google-oauth.path;

    # Nginx reverse proxy with CORS for dashboard and CLI OIDC flows.
    # Listens on both VPN service IP and WG tunnel IP so vpsfree can proxy
    # dex traffic for clients that haven't joined the mesh yet.
    services.nginx.virtualHosts.${dexDomain} = {
      listenAddresses = [cfg.ip config.homelab.tunnel.ip];
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port.dex}";
        recommendedProxySettings = true;
        extraConfig = ''
          # CORS: dashboard SPA fetches OIDC discovery cross-origin
          add_header Access-Control-Allow-Origin "https://netbird.${domain}" always;
          add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
          add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;

          if ($request_method = OPTIONS) {
            return 204;
          }
        '';
      };
    };

    # Dex metrics via unified metrics proxy
    services.nginx.virtualHosts."metrics".locations."/metrics/dex".proxyPass = "http://127.0.0.1:${toString cfg.port.metrics}/metrics";

    homelab.scrapeTargets = [
      {
        job = "dex";
        metricsPath = "/metrics/dex";
      }
    ];

    homelab.alerts.dex = [
      {
        alert = "DexDown";
        expr = ''up{job="dex"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Dex OIDC provider is down";
      }
    ];

    homelab.healthChecks = [
      {
        name = "Dex";
        script = pkgs.writeShellApplication {
          name = "health-check-dex";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet dex.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

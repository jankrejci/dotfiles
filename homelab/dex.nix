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

    port = lib.mkOption {
      type = lib.types.port;
      default = 5556;
      description = "Port for Dex server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "dex";
      description = "Subdomain for Dex";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [dexDomain];

    # Allow HTTPS on VPN interface
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
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
          http = "127.0.0.1:${toString cfg.port}";
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
        # Secrets loaded from files in /var/lib/dex/secrets/
        staticClients = [
          {
            id = "grafana";
            name = "Grafana";
            redirectURIs = ["https://grafana.${domain}/login/generic_oauth"];
            secretFile = "/var/lib/dex/secrets/grafana-client-secret";
          }
          {
            id = "immich";
            name = "Immich";
            redirectURIs = [
              "https://immich.${domain}/auth/login"
              "https://immich.${domain}/user-settings"
              "https://immich.${domain}/api/oauth/mobile-redirect"
            ];
            secretFile = "/var/lib/dex/secrets/immich-client-secret";
          }
          {
            id = "memos";
            name = "Memos";
            redirectURIs = ["https://memos.${domain}/auth/callback"];
            secretFile = "/var/lib/dex/secrets/memos-client-secret";
          }
          {
            id = "jellyfin";
            name = "Jellyfin";
            redirectURIs = ["https://jellyfin.${domain}/sso/OID/redirect/Dex"];
            secretFile = "/var/lib/dex/secrets/jellyfin-client-secret";
          }
        ];
      };
    };

    # Ensure dex starts after PostgreSQL
    systemd.services.dex.after = ["postgresql.service"];
    systemd.services.dex.requires = ["postgresql.service"];
    systemd.services.dex.serviceConfig.EnvironmentFile = "/var/lib/dex/secrets/google-oauth";

    # Secrets directory for Google OAuth and client secrets
    systemd.tmpfiles.rules = [
      "d /var/lib/dex/secrets 0750 dex dex -"
    ];

    # Nginx reverse proxy
    services.nginx.virtualHosts.${dexDomain} = {
      listenAddresses = [cfg.ip];
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        recommendedProxySettings = true;
      };
    };
  };
}

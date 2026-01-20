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
# Secret management: Services declare their secrets via homelab.secrets with
# register = "dex". The inject-secrets script calls dex.registerHandler to
# write the secret to dex's secrets directory. Dex reads secrets from files.
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

  # Secret path for Google OAuth credentials
  googleOAuthPath = "/var/lib/dex/secrets/google-oauth";

  # Handler for registering Dex client secrets.
  # Called by inject-secrets with client_id as $1 and secret on stdin.
  registerHandler = pkgs.writeShellApplication {
    name = "dex-register";
    runtimeInputs = [pkgs.systemd];
    text = ''
      client_id="$1"
      secret=$(cat)

      # Write secret to dex's secrets directory atomically
      install -d -m 700 -o dex -g dex /var/lib/dex/secrets
      temp_file=$(mktemp /var/lib/dex/secrets/.tmp.XXXXXX)
      echo -n "$secret" > "$temp_file"
      chown dex:dex "$temp_file"
      chmod 600 "$temp_file"
      mv "$temp_file" "/var/lib/dex/secrets/$client_id"
      systemctl restart dex
    '';
  };
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

    # Expose registerHandler so inject-secrets can find it
    registerHandler = lib.mkOption {
      type = lib.types.package;
      default = registerHandler;
      description = "Handler script for registering Dex clients";
      internal = true;
    };

    # Client registrations for staticClients configuration.
    # Services add entries here, dex generates staticClients from them.
    clients = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.str;
            description = "Client ID used in OAuth flow";
          };
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name shown in Dex login";
          };
          redirectURIs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Allowed OAuth redirect URIs";
          };
        };
      });
      default = [];
      description = "OAuth clients that authenticate via Dex";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.postgresql.enable;
        message = "homelab.dex requires homelab.postgresql.enable = true";
      }
    ];

    # Google OAuth credentials secret, user provides GOOGLE_CLIENT_ID and
    # GOOGLE_CLIENT_SECRET in KEY=value format when prompted.
    homelab.secrets.google-oauth = {
      generate = "ask";
      handler = pkgs.writeShellApplication {
        name = "dex-google-oauth-handler";
        runtimeInputs = [pkgs.systemd];
        text = ''
          install -d -m 700 -o dex -g dex /var/lib/dex/secrets
          install -m 600 -o dex -g dex /dev/stdin ${googleOAuthPath}
          systemctl restart dex
        '';
      };
    };

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

        # Emergency fallback credentials for when Google OAuth is unavailable.
        # These are not primary authentication, use Google sign-in for normal access.
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
        # Credentials loaded from environment via sops-nix
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

        # Downstream OAuth clients generated from homelab.dex.clients
        staticClients =
          map (client: {
            inherit (client) id name redirectURIs;
            secretFile = "/var/lib/dex/secrets/${client.id}";
          })
          cfg.clients;
      };
    };

    # Ensure dex starts after PostgreSQL
    systemd.services.dex.after = ["postgresql.service"];
    systemd.services.dex.requires = ["postgresql.service"];
    systemd.services.dex.serviceConfig.EnvironmentFile = googleOAuthPath;

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

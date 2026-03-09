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
# - Zitadel: see detailed evaluation below
# - Kanidm: declarative OIDC clients but no upstream IdP federation, so no
#   Google OAuth. Dealbreaker until upstream adds it.
# - Authelia: certified OIDC provider with sessions, but no NixOS module.
#   Pairing with LLDAP adds user management. Worth revisiting if a NixOS
#   module appears.
# - Dex: ~100MB RAM, stable NixOS module, simple YAML config
#
# Known limitations of Dex:
# - No SSO sessions. Each service login triggers full re-authentication.
#   Open issue since 2015, still unmerged.
# - No user management UI. staticPasswords in YAML is the only local option.
# - No session persistence or "remember me" cookie.
#
# Dex is a lightweight proxy, not a user database. User management happens in
# upstream providers.
#
# Adding LLDAP behind Dex as an LDAP connector would solve user management
# with a web UI, but does nothing for session persistence. Session persistence
# requires the OIDC provider itself to maintain sessions, which Dex refuses
# to do by design.
#
# Zitadel evaluation (2026-03, branch jkr/zitadel):
#
# Zitadel provides true SSO sessions, admin console, user management, and
# Google OAuth as upstream IdP. A full prototype was built: module with
# service, nginx, postgres, OpenTofu-based OIDC app provisioning, and all
# services switched over.
#
# Fundamental problem: Zitadel auto-generates client IDs and secrets when
# OIDC apps are created via API. They cannot be predetermined or set to
# custom values. The steps.yaml bootstrap config only supports creating
# instances, orgs, and users, not OIDC applications. This means credentials
# are only known after Zitadel is running and apps are created via the
# Management API.
#
# Approaches explored and rejected:
# - Two-phase deployment: deploy Zitadel, run setup script, get credentials,
#   update config, redeploy. Unacceptable for nixos-install workflow.
# - Systemd oneshot after boot: creates apps via API, writes credentials to
#   files, services read at runtime. Works but every service needs runtime
#   credential injection, the Netbird dashboard bakes client ID into a static
#   derivation at build time, and the whole approach fights NixOS declarative
#   model where config should be known at build time.
# - OpenTofu as systemd service: same problems plus heavy runtime dependency.
#
# Dex works because client IDs are static strings in config and secrets are
# pre-generated in agenix. Everything is fully declarative and known at build
# time. This is the correct model for NixOS.
#
# Revisit Zitadel if upstream adds declarative client provisioning via
# steps.yaml or allows setting custom client IDs and secrets via API.
#
# Local password database is enabled for fallback access when Google is down.
{
  config,
  lib,
  pkgs,
  inputs,
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
      default = "auth";
      description = "Subdomain for Dex";
    };

    # Decentralized client registry. Each service module declares its dex
    # client here. The dex module aggregates clients from all hosts and
    # auto-generates age.secrets and staticClients configuration.
    clients = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.str;
            description = "OIDC client ID";
          };
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name shown on Dex consent screen";
          };
          redirectURIs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "OAuth2 callback URLs";
          };
          public = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Public client for SPAs that cannot hold a secret";
          };
          secretRekeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Path to agenix secret file for this client";
          };
        };
      });
      default = [];
      description = "Dex OIDC client registrations from service modules";
    };
  };

  config = lib.mkIf cfg.enable (let
    # Collect dex client registrations from all nixos hosts
    allConfigs = inputs.self.nixosConfigurations;
    nixosHostNames = lib.attrNames (
      lib.filterAttrs (
        _: host:
          (host.kind or "nixos") == "nixos"
      )
      config.homelab.hosts
    );
    allClients = lib.flatten (
      map (
        name: allConfigs.${name}.config.homelab.dex.clients
      )
      nixosHostNames
    );

    # Non-public clients need dex-side secret declarations
    secretClients = builtins.filter (c: !c.public) allClients;

    clientsWithMissingSecrets = builtins.filter (c: c.secretRekeyFile == null) secretClients;

    # Auto-generate age.secrets for each non-public client
    clientSecrets = lib.listToAttrs (
      map (client: {
        name = "dex-${client.id}-secret";
        value = {
          rekeyFile = client.secretRekeyFile;
          owner = "dex";
        };
      })
      secretClients
    );

    # Auto-generate staticClients from all collected clients
    clientConfigs = map (client:
      {
        inherit (client) id name redirectURIs;
      }
      // lib.optionalAttrs client.public {
        public = true;
      }
      // lib.optionalAttrs (!client.public) {
        secretFile = config.age.secrets."dex-${client.id}-secret".path;
      })
    allClients;
  in {
    assertions = [
      {
        assertion = config.homelab.tunnel.enable;
        message = "dex requires homelab.tunnel for vpsfree SSO proxy";
      }
      {
        assertion = clientsWithMissingSecrets == [];
        message = "dex: non-public clients must set secretRekeyFile: ${
          lib.concatMapStringsSep ", " (c: c.id) clientsWithMissingSecrets
        }";
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

    # Google OAuth credentials for upstream identity provider.
    # Client secrets auto-generated from cross-host dex.clients registry.
    age.secrets =
      {
        google-oauth = {
          rekeyFile = ../secrets/google-oauth.age;
          owner = "dex";
        };
      }
      // clientSecrets;

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

        frontend.theme = "dark";

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

        # Downstream OAuth clients collected from cross-host dex.clients registry
        staticClients = clientConfigs;
      };
    };

    # Ensure dex starts after PostgreSQL and network is online.
    # Dex fetches Google OIDC discovery at startup which needs working DNS.
    systemd.services.dex.after = ["postgresql.service" "network-online.target"];
    systemd.services.dex.requires = ["postgresql.service"];
    systemd.services.dex.wants = ["network-online.target"];
    systemd.services.dex.serviceConfig.EnvironmentFile = config.age.secrets.google-oauth.path;
    # Dex is Kubernetes-first and exposes /healthz/ready for k8s probes but
    # does not implement sd_notify. The NixOS module uses Type=simple, so
    # systemd considers it started the instant the process forks, before the
    # HTTP port is bound. Override to Type=notify with a wrapper that polls
    # the HTTP port and sends READY=1, bridging k8s-style health checks to
    # systemd readiness. This ensures After=dex.service actually waits.
    systemd.services.dex.serviceConfig.Type = lib.mkForce "notify";
    systemd.services.dex.serviceConfig.NotifyAccess = "all";
    systemd.services.dex.serviceConfig.ExecStart = let
      dexBin = "${config.services.dex.package}/bin/dex";
      metricsPort = toString cfg.port.metrics;
    in
      lib.mkForce "${pkgs.writeShellScript "dex-notify-start" ''
        ${dexBin} serve /run/dex/config.yaml &

        attempts=0
        while ! ${pkgs.curl}/bin/curl -sf http://127.0.0.1:${metricsPort}/healthz/ready > /dev/null 2>&1; do
          attempts=$((attempts + 1))
          test "$attempts" -lt 100 || {
            echo "dex HTTP not ready after 10s" >&2
            exit 1
          }
          ${pkgs.coreutils}/bin/sleep 0.1
        done

        ${pkgs.systemd}/bin/systemd-notify --ready
        wait
      ''}";

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
  });
}

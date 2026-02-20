# Netbird server: management and relay
#
# Control plane and connectivity services for the mesh VPN. Management stores
# peer configs, groups, policies, routes, and DNS settings in PostgreSQL.
# Relay provides a fallback path when direct peer-to-peer connections fail.
#
# Signal runs on vpsfree to avoid pprof port 6060 conflict with management.
# Both Go binaries hardcode pprof to 127.0.0.1:6060 with no config option.
# TODO: migrate to combined netbird-server binary (available since v0.65.0)
# which eliminates the conflict by running everything in one process.
#
# vpsfree acts as a stateless public proxy, forwarding management and relay
# traffic here via WG backup tunnel.
#
# The dashboard is a static web UI for admin access, served behind VPN only.
# Authentication: external Dex OIDC for SSO with Google OAuth and local
# password fallback. Netbird v0.62+ embeds its own Dex but we ignore it
# and point management to our external Dex via oidcConfigEndpoint.
#
# Account-level settings like network_range, dns_domain, and
# lazy_connection_enabled live in the management database, not config files.
# Manage them via the dashboard UI or REST API.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.netbird-server;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  apiDomain = "api.${domain}";
  dashboardDomain = "${cfg.subdomain}.${domain}";
  dexDomain = "dex.${domain}";

  wgIp = config.homelab.tunnel.ip;
  certDir = config.security.acme.certs.${domain}.directory;

  # STUN is a stateless protocol that tells a client its public IP:port mapping.
  # No credentials or data flow through the STUN server. Google operates free
  # public STUN servers that are the de-facto standard for WebRTC and VPN tools.
  googleStunUri = "stun:stun.l.google.com:19302";
in {
  options.homelab.netbird-server = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Netbird management server and dashboard";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "Service IP for the dashboard web UI";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "netbird";
      description = "Subdomain for dashboard";
    };

    port = {
      management = lib.mkOption {
        type = lib.types.port;
        description = "Management API listen port";
      };

      metrics = lib.mkOption {
        type = lib.types.port;
        description = "Management metrics listen port";
      };

      relayMetrics = lib.mkOption {
        type = lib.types.port;
        description = "Relay metrics listen port";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.tunnel.enable;
        message = "netbird-server requires homelab.tunnel to be enabled";
      }
    ];

    # Encryption key for sensitive data stored in management database
    age.secrets.netbird-datastore-key = {
      rekeyFile = ../secrets/netbird-datastore-key.age;
      owner = "netbird-mgmt";
    };

    # Relay auth secret shared between management config and relay service
    age.secrets.netbird-relay-secret = {
      rekeyFile = ../secrets/netbird-relay-secret.age;
      mode = "0440";
      owner = "netbird-mgmt";
      group = "nginx";
    };

    # Relay server for fallback traffic when direct peer-to-peer fails.
    # Uses WebSocket-based DERP protocol over TLS with ACME certificates.
    # Relay runs on its own port with own TLS because DERP cannot be
    # reliably proxied through nginx.
    systemd.services.netbird-relay = {
      description = "Netbird relay server";
      after = ["network.target" "acme-${domain}.service"];
      wants = ["acme-${domain}.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = let
          relayBin = "${pkgs.unstable.netbird-relay}/bin/netbird-relay";
          secretPath = config.age.secrets.netbird-relay-secret.path;
        in
          pkgs.writeShellScript "netbird-relay-start" ''
            exec ${relayBin} \
              --listen-address "${wgIp}:${toString services.netbird.port.relay}" \
              --exposed-address "rels://${apiDomain}:${toString services.netbird.port.relay}" \
              --auth-secret "$(cat ${secretPath})" \
              --tls-cert-file "${certDir}/fullchain.pem" \
              --tls-key-file "${certDir}/key.pem" \
              --metrics-port ${toString cfg.port.relayMetrics} \
              --log-file console \
              --log-level info
          '';
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = true;
        SupplementaryGroups = ["nginx"];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    # Create management user early so agenix can chown secrets during activation.
    # Must match the PostgreSQL role name for peer authentication.
    users.users.netbird-mgmt = {
      isSystemUser = true;
      group = "netbird-mgmt";
    };
    users.groups.netbird-mgmt = {};

    # Register dashboard IP on services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [dashboardDomain];

    # Allow HTTPS on VPN interface for dashboard access
    networking.firewall.interfaces.${services.netbird.interface}.allowedTCPPorts = [
      services.https.port
    ];

    # Allow HTTPS and relay on WG tunnel for vpsfree proxy
    networking.firewall.interfaces."wg0".allowedTCPPorts = [
      services.https.port
      services.netbird.port.relay
    ];

    # PostgreSQL database for management server state
    services.postgresql = {
      ensureDatabases = ["netbird-mgmt"];
      ensureUsers = [
        {
          name = "netbird-mgmt";
          ensureDBOwnership = true;
        }
      ];
    };

    # Management server: the Netbird control plane
    services.netbird.server.management = {
      enable = true;
      package = pkgs.unstable.netbird-management;
      domain = apiDomain;
      port = cfg.port.management;
      metricsPort = cfg.port.metrics;
      dnsDomain = global.peerDomain;
      singleAccountModeDomain = global.peerDomain;
      oidcConfigEndpoint = "https://${dexDomain}/.well-known/openid-configuration";

      settings = {
        # PostgreSQL backend via Unix socket with peer authentication
        StoreConfig = {
          Engine = "postgres";
          Connection = "postgresql:///netbird-mgmt?host=/run/postgresql";
        };

        DataStoreEncryptionKey._secret =
          config.age.secrets.netbird-datastore-key.path;

        # No coturn TURN server, relay handles fallback traffic.
        # Override Secret to suppress world-readable nix store warning
        # from the NixOS module default of "not-secure-secret".
        TURNConfig = {
          Turns = [];
          TimeBasedCredentials = false;
          Secret._secret = config.age.secrets.netbird-relay-secret.path;
        };

        # Public STUN for NAT traversal
        Stuns = [
          {
            Proto = "udp";
            URI = googleStunUri;
          }
        ];

        # Signal server runs locally, clients reach it via vpsfree proxy
        Signal = {
          Proto = "https";
          URI = "${apiDomain}:${toString services.https.port}";
          Username = "";
          Password = null;
        };

        # Relay server runs locally, clients reach it via vpsfree proxy
        Relay = {
          Addresses = ["rels://${apiDomain}:${toString services.netbird.port.relay}"];
          CredentialsTTL = "12h";
          Secret._secret = config.age.secrets.netbird-relay-secret.path;
        };

        # PKCE flow for mobile apps and desktop clients
        PKCEAuthorizationFlow = {
          ProviderConfig = {
            Audience = "netbird";
            ClientID = "netbird";
            ClientSecret = "";
            AuthorizationEndpoint = "https://${dexDomain}/auth";
            TokenEndpoint = "https://${dexDomain}/token";
            Scope = "openid profile email";
            # Port 53000 is hardcoded in the Netbird client PKCE callback listener
            RedirectURLs = ["http://localhost:53000"];
            UseIDToken = true;
          };
        };

        # Device authorization flow for headless CLI login
        DeviceAuthorizationFlow = {
          ProviderConfig = {
            Audience = "netbird";
            ClientID = "netbird";
            ClientSecret = "";
            TokenEndpoint = "https://${dexDomain}/token";
            DeviceAuthEndpoint = "https://${dexDomain}/device/code";
            Scope = "openid profile email";
            UseIDToken = true;
          };
        };
      };
    };

    # Management must start after PostgreSQL and run as the netbird-mgmt user
    # for PostgreSQL peer authentication to work.
    # v0.64+ requires NETBIRD_STORE_ENGINE_POSTGRES_DSN as env var instead of
    # reading StoreConfig.Connection from management.json.
    systemd.services.netbird-management = {
      after = ["postgresql.service" "dex.service"];
      requires = ["postgresql.service" "dex.service"];
      environment.NETBIRD_STORE_ENGINE_POSTGRES_DSN = "postgresql:///netbird-mgmt?host=/run/postgresql";
      serviceConfig.User = "netbird-mgmt";
      serviceConfig.Group = "netbird-mgmt";
    };

    # Dashboard: static admin web UI served by nginx behind VPN
    services.netbird.server.dashboard = {
      enable = true;
      package = pkgs.unstable.netbird-dashboard;
      domain = dashboardDomain;
      managementServer = "https://${apiDomain}";
      settings = {
        AUTH_AUTHORITY = "https://${dexDomain}";
        AUTH_CLIENT_ID = "netbird";
        AUTH_SUPPORTED_SCOPES = "openid profile email";
        NETBIRD_TOKEN_SOURCE = "idToken";
      };
    };

    # Dashboard: VPN-only access on service IP
    services.nginx.virtualHosts.${dashboardDomain} = {
      listenAddresses = [cfg.ip];
      forceSSL = true;
      useACMEHost = domain;
      root = config.services.netbird.server.dashboard.finalDrv;
      locations."/" = {
        tryFiles = "$uri $uri/ /index.html";
      };
    };

    # Management API: accessible from vpsfree via WG backup tunnel.
    # vpsfree's nginx proxies public api.krejci.io requests here.
    services.nginx.virtualHosts.${apiDomain} = {
      listenAddresses = [wgIp];
      forceSSL = true;
      useACMEHost = domain;

      # REST API
      locations."/api" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port.management}";
        recommendedProxySettings = true;
      };

      # gRPC for peer synchronization.
      # NixOS proxyPass only generates proxy_pass which does not support
      # gRPC schemes. Use grpc_pass directive directly via extraConfig.
      locations."/management.ManagementService/" = {
        extraConfig = ''
          grpc_pass grpc://127.0.0.1:${toString cfg.port.management};
          grpc_read_timeout 1d;
          grpc_send_timeout 1d;
          grpc_socket_keepalive on;
        '';
      };
    };

    # Netbird metrics via unified metrics proxy
    services.nginx.virtualHosts."metrics".locations."/metrics/netbird-mgmt".proxyPass = "http://127.0.0.1:${toString cfg.port.metrics}/metrics";
    services.nginx.virtualHosts."metrics".locations."/metrics/netbird-relay".proxyPass = "http://127.0.0.1:${toString cfg.port.relayMetrics}/metrics";

    homelab.scrapeTargets = [
      {
        job = "netbird-mgmt";
        metricsPath = "/metrics/netbird-mgmt";
      }
      {
        job = "netbird-relay";
        metricsPath = "/metrics/netbird-relay";
      }
    ];

    homelab.alerts.netbird = [
      {
        alert = "NetbirdManagementDown";
        expr = ''up{job="netbird-mgmt"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Netbird management server is down";
      }
      {
        alert = "NetbirdRelayDown";
        expr = ''up{job="netbird-relay"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Netbird relay server is down";
      }
    ];

    homelab.dashboardEntries = [
      {
        name = "Netbird";
        url = "https://${dashboardDomain}";
        icon = ../assets/dashboard-icons/netbird.svg;
      }
    ];

    homelab.healthChecks = [
      {
        name = "Netbird Management";
        script = pkgs.writeShellApplication {
          name = "health-check-netbird-mgmt";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet netbird-management.service
          '';
        };
        timeout = 10;
      }
      {
        name = "Netbird Relay";
        script = pkgs.writeShellApplication {
          name = "health-check-netbird-relay";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet netbird-relay.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

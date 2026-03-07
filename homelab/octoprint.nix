# OctoPrint 3D printer control
#
# - web interface for Prusa printer
# - Obico AI failure detection plugin
# - Prometheus metrics exporter
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.octoprint;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  allHosts = config.homelab.hosts;
  serverDomain = "${cfg.subdomain}.${domain}";
  dexDomain = "${config.homelab.dex.subdomain}.${domain}";

  mkObicoPlugin = ps:
    ps.callPackage ../pkgs/octoprint-obico.nix {};
  mkPrometheusPlugin = ps:
    ps.callPackage ../pkgs/octoprint-prometheus-exporter.nix {};
in {
  options.homelab.octoprint = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable OctoPrint 3D printer control";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      description = "Port for OctoPrint server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "octoprint";
      description = "Subdomain for OctoPrint";
    };

    dexHost = lib.mkOption {
      type = lib.types.str;
      description = "Hostname running Dex, for /etc/hosts resolution of the Dex domain";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [serverDomain];

    # Resolve Dex domain to its VPN service IP so oauth2-proxy talks to
    # the Dex host directly over the mesh instead of routing through the public proxy.
    networking.hosts.${allHosts.${cfg.dexHost}.homelab.dex.ip} = [dexDomain];

    # oauth2-proxy environment file with client secret and cookie secret
    age.secrets.oauth2-proxy-env = {
      rekeyFile = ../secrets/oauth2-proxy-env.age;
      owner = "oauth2-proxy";
    };

    # OctoPrint API key for prometheus metrics scraping
    age.secrets.octoprint-metrics-api-key = {
      rekeyFile = ../secrets/octoprint-metrics-api-key.age;
      owner = "nginx";
    };

    # Allow HTTPS on VPN interface
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

    # OctoPrint has no native OIDC support, so oauth2-proxy acts as an
    # authentication gateway. It intercepts all requests via nginx auth_request,
    # authenticates users through Dex, and passes the verified email to
    # OctoPrint as REMOTE_USER header for automatic session creation.
    services.oauth2-proxy = {
      enable = true;
      provider = "oidc";
      clientID = "octoprint";
      keyFile = config.age.secrets.oauth2-proxy-env.path;
      redirectURL = "https://${serverDomain}/oauth2/callback";
      oidcIssuerUrl = "https://${dexDomain}";
      reverseProxy = true;
      setXauthrequest = true;
      email.domains = ["*"];
      scope = "openid email profile";
      cookie.secure = true;
      extraConfig = {
        # Skip the "click to sign in" intermediate page
        skip-provider-button = true;
        code-challenge-method = "S256";
      };
      nginx = {
        domain = serverDomain;
        virtualHosts.${serverDomain} = {};
      };
    };

    services.octoprint = {
      enable = true;
      # Listen on localhost only, accessed via nginx proxy
      host = "127.0.0.1";
      port = cfg.port;
      plugins = ps: [
        (mkObicoPlugin ps)
        (mkPrometheusPlugin ps)
      ];
      extraConfig = {
        # Safe to trust REMOTE_USER because nginx auth_request blocks all
        # unauthenticated requests before they reach OctoPrint. Without a
        # valid Dex session, oauth2-proxy returns 401 and nginx redirects
        # to login. First login auto-creates a non-admin user that must be
        # promoted manually once.
        accessControl = {
          trustRemoteUser = true;
          addRemoteUsers = true;
        };
        webcam = {
          # Use nginx-proxied URLs so browser can access the stream
          stream = "/webcam/stream";
          snapshot = "/webcam/snapshot";
        };
        plugins = {
          obico = {
            # WebRTC streaming disabled. Caused system crashes on RPi Zero 2 W
            # due to CPU load from libx264 encoding. Snapshot-only mode is stable
            # and sufficient for AI failure detection.
            disable_video_streaming = true;
          };
        };
      };
    };

    # Wait for services interface before binding
    systemd.services.nginx.after = ["sys-subsystem-net-devices-services.device"];

    # Generate nginx snippet with OctoPrint metrics API key at runtime so the
    # key stays out of the nix store and git history.
    systemd.services.nginx.preStart = lib.mkBefore ''
      mkdir -p /run/nginx
      key=$(cat "${config.age.secrets.octoprint-metrics-api-key.path}")
      echo "proxy_set_header X-Api-Key \"$key\";" > /run/nginx/octoprint-api-key.conf
    '';

    services.nginx = {
      enable = true;
      virtualHosts.${serverDomain} = {
        listen = [
          {
            addr = cfg.ip;
            port = services.https.port;
            ssl = true;
          }
        ];
        onlySSL = true;
        useACMEHost = domain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
          extraConfig = ''
            # Forward authenticated email to OctoPrint for SSO login.
            # $email is set by the oauth2-proxy nginx module via auth_request_set.
            proxy_set_header REMOTE_USER $email;
          '';
        };
        # Webcam proxy config from webcam module
        locations."/webcam/" = config.homelab.webcam.nginxLocation;
      };
      # OctoPrint metrics via unified metrics proxy
      # Dedicated prometheus user with only PLUGIN_PROMETHEUS_EXPORTER_SCRAPE permission
      # Metrics API key is managed via agenix secret octoprint-metrics-api-key
      virtualHosts."metrics".locations."/metrics/octoprint" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}/plugin/prometheus_exporter/metrics";
        extraConfig = ''
          include /run/nginx/octoprint-api-key.conf;
        '';
      };
    };

    # Scrape target for prometheus
    homelab.scrapeTargets = [
      {
        job = "octoprint";
        metricsPath = "/metrics/octoprint";
      }
    ];

    # Alert rules for octoprint with oneshot label to prevent repeat notifications
    homelab.alerts.octoprint = [
      {
        alert = "OctoprintDown";
        expr = ''up{job="octoprint"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
          oneshot = "true";
        };
        annotations.summary = "OctoPrint is down";
      }
    ];

    homelab.dashboardEntries = [
      {
        name = "OctoPrint";
        url = "https://${serverDomain}";
        icon = ../assets/dashboard-icons/octoprint.svg;
      }
    ];

    homelab.healthChecks = [
      {
        name = "OctoPrint";
        script = pkgs.writeShellApplication {
          name = "health-check-octoprint";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet octoprint.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}

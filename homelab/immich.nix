# Immich photo library service
#
# - Google Photos alternative with ML features
# - PostgreSQL and Redis backends with borg backup
# - metrics on port 8081/8082, Dex SSO
# - pinned to nixpkgs-immich input for controlled updates
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.immich;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  immichDomain = "${cfg.subdomain}.${domain}";
  httpsPort = services.https.port;

  # Internal metrics ports for exporters
  immichApiMetricsPort = 8081;
  immichMicroservicesMetricsPort = 8082;

  # Second disk for Immich data (NVMe)
  # Assumes partition is already created with label "disk-immich-luks"
  luksDevice = "/dev/disk/by-partlabel/disk-immich-luks";

  # OAuth configuration for Dex SSO integration.
  # Immich only supports OAuth config via JSON file or web UI, not environment
  # variables. We generate a template here and substitute the secret at runtime
  # to avoid storing secrets in the Nix store.
  immichOAuthConfigTemplate = pkgs.writeText "immich-oauth-template.json" (builtins.toJSON {
    oauth = {
      enabled = true;
      issuerUrl = "https://dex.${domain}";
      clientId = "immich";
      clientSecret = "@IMMICH_OAUTH_CLIENT_SECRET@";
      scope = "openid email profile";
      buttonText = "Login with SSO";
      autoRegister = true;
      autoLaunch = true;
      mobileOverrideEnabled = true;
      mobileRedirectUri = "https://immich.${domain}/api/oauth/mobile-redirect";
    };
    # Disable password login, force OAuth through Dex
    passwordLogin.enabled = false;
  });
  immichOAuthConfigPath = "/var/lib/immich/config.json";
in {
  options.homelab.immich = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Immich photo library";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      description = "Port for Immich server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "immich";
      description = "Subdomain for Immich";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Dex client secret for SSO authentication
      age.secrets.immich-dex-secret = {
        rekeyFile = ../secrets/dex-immich-secret.age;
        owner = "immich";
      };

      # Register IP for services dummy interface
      homelab.serviceIPs = [cfg.ip];
      networking.hosts.${cfg.ip} = [immichDomain];

      # Allow HTTPS on VPN interface (nginx proxies to Immich for both web and mobile)
      networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [httpsPort];

      # Use shared redis from homelab.redis instead of immich-managed instance.
      # enable=false disables the dedicated redis-immich service.
      # host/port still configure where immich connects.
      services.immich.redis = {
        enable = false;
        host = "127.0.0.1";
        port = 6379;
      };

      # NVMe data disk - TPM encrypted, not touched during deployment
      boot.initrd.luks.devices."immich-data" = {
        device = luksDevice;
        allowDiscards = true;
      };

      # Mount NVMe to /mnt/immich-data
      fileSystems."/mnt/immich-data" = {
        device = "/dev/mapper/immich-data";
        fsType = "ext4";
        options = ["defaults"];
      };

      # Bind mount immich data
      fileSystems."/var/lib/immich" = {
        device = "/mnt/immich-data/immich";
        fsType = "none";
        options = ["bind" "x-systemd.requires=mnt-immich\\x2ddata.mount"];
      };

      # Bind mount borg repos
      fileSystems."/var/lib/borg-repos" = {
        device = "/mnt/immich-data/borg-repos";
        fsType = "none";
        options = ["bind" "x-systemd.requires=mnt-immich\\x2ddata.mount"];
      };

      services.immich = {
        enable = true;
        package = pkgs.immich-pinned.immich;
        # Listen on 127.0.0.1 only, accessed via nginx proxy
        host = "127.0.0.1";
        port = cfg.port;
        # Media stored on dedicated NVMe disk at /var/lib/immich (default)
        environment = {
          PUBLIC_IMMICH_SERVER_URL = "https://share.${domain}";
          IMMICH_CONFIG_FILE = immichOAuthConfigPath;
          # Enable Prometheus metrics on 127.0.0.1
          IMMICH_TELEMETRY_INCLUDE = "all";
          IMMICH_API_METRICS_PORT = toString immichApiMetricsPort;
          IMMICH_MICROSERVICES_METRICS_PORT = toString immichMicroservicesMetricsPort;
        };
      };

      # Generate OAuth config at runtime by substituting secret into template.
      # Runs as root before service starts. Immich reads file via IMMICH_CONFIG_FILE.
      systemd.services.immich-server.preStart = ''
        secret=$(cat "${config.age.secrets.immich-dex-secret.path}")
        ${pkgs.gnused}/bin/sed "s/@IMMICH_OAUTH_CLIENT_SECRET@/$secret/" \
          "${immichOAuthConfigTemplate}" > "${immichOAuthConfigPath}"
      '';

      # Ensure required directory structure exists on the data disk
      systemd.tmpfiles.rules = [
        # Base directories on mount point
        "d /mnt/immich-data/immich 0755 immich immich -"
        "d /mnt/immich-data/borg-repos 0755 root root -"
        "d /mnt/immich-data/borg-repos/immich 0700 root root -"
        # Immich subdirectories
        "d /var/lib/immich/upload 0755 immich immich -"
        "d /var/lib/immich/library 0755 immich immich -"
        "d /var/lib/immich/thumbs 0755 immich immich -"
        "d /var/lib/immich/profile 0755 immich immich -"
        "d /var/lib/immich/encoded-video 0755 immich immich -"
        "d /var/lib/immich/backups 0755 immich immich -"
        "f /var/lib/immich/upload/.immich 0644 immich immich -"
        "f /var/lib/immich/library/.immich 0644 immich immich -"
        "f /var/lib/immich/thumbs/.immich 0644 immich immich -"
        "f /var/lib/immich/profile/.immich 0644 immich immich -"
        "f /var/lib/immich/encoded-video/.immich 0644 immich immich -"
        "f /var/lib/immich/backups/.immich 0644 immich immich -"
      ];

      # Nginx reverse proxy - accessible via immich.<domain>
      services.nginx.virtualHosts.${immichDomain} = {
        listenAddresses = [cfg.ip];
        forceSSL = true;
        useACMEHost = "${domain}";
        # Allow large file uploads for photos and videos
        extraConfig = ''
          client_max_body_size 1G;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };

      # Immich metrics via unified metrics proxy
      services.nginx.virtualHosts."metrics".locations = {
        "/metrics/immich".proxyPass = "http://127.0.0.1:${toString immichApiMetricsPort}/metrics";
        "/metrics/immich-microservices".proxyPass = "http://127.0.0.1:${toString immichMicroservicesMetricsPort}/metrics";
      };

      # Scrape targets for prometheus
      homelab.scrapeTargets = [
        {
          job = "immich";
          metricsPath = "/metrics/immich";
        }
        {
          job = "immich-microservices";
          metricsPath = "/metrics/immich-microservices";
        }
      ];

      # Alert rules for immich service
      homelab.alerts.immich = [
        {
          alert = "ImmichDown";
          expr = ''up{job="immich"} == 0'';
          labels = {
            severity = "critical";
            host = config.homelab.host.hostName;
            type = "service";
          };
          annotations.summary = "Immich server is down";
        }
        {
          alert = "ImmichMicroservicesDown";
          expr = ''up{job="immich-microservices"} == 0'';
          labels = {
            severity = "critical";
            host = config.homelab.host.hostName;
            type = "service";
          };
          annotations.summary = "Immich microservices are down";
        }
      ];

      homelab.dashboardEntries = [
        {
          name = "Immich";
          url = "https://${immichDomain}";
          icon = ../assets/dashboard-icons/immich.svg;
        }
      ];

      homelab.healthChecks = [
        {
          name = "Immich";
          script = pkgs.writeShellApplication {
            name = "health-check-immich";
            runtimeInputs = [pkgs.systemd];
            text = ''
              systemctl is-active --quiet immich-server.service
            '';
          };
          timeout = 10;
        }
        {
          name = "Immich ML";
          script = pkgs.writeShellApplication {
            name = "health-check-immich-ml";
            runtimeInputs = [pkgs.systemd];
            text = ''
              systemctl is-active --quiet immich-machine-learning.service
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
          name = "immich";
          paths = ["/var/lib/immich"];
          excludes = [
            "/var/lib/immich/thumbs"
            "/var/lib/immich/encoded-video"
          ];
          database = "immich";
          service = "immich-server";
          hour = 2;
        }
      ];
    }
  ]);
}

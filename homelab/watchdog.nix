# External watchdog monitoring
#
# Runs a separate prometheus instance with email-only alerting to detect when the
# primary monitoring pipeline (prometheus + ntfy on thinkcenter) goes down.
# Services enroll via homelab.X.watchdog = true which registers watchdogTargets.
# This module auto-generates up/down alerts for each enrolled service and host.
#
# Architecture:
# - Scrapes node exporter + watchdog-enrolled jobs from enrolled hosts
# - Alerts via email through Protonmail Bridge (no ntfy dependency)
# - Short retention since this is purely for alerting, not dashboards
{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.homelab.watchdog;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  peerDomain = global.peerDomain;
  watchdogDomain = "${cfg.subdomain}.${domain}";
  metricsPort = toString services.metrics.port;
  promPort = toString cfg.port;
  alertmanagerPort = toString cfg.alertmanagerPort;
in {
  options.homelab.watchdog = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable external watchdog monitoring";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "watchdog";
      description = "Subdomain for watchdog prometheus UI";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9095;
      description = "Port for watchdog prometheus instance";
    };

    alertmanagerPort = lib.mkOption {
      type = lib.types.port;
      default = 9094;
      description = "Port for watchdog alertmanager";
    };

    retention = lib.mkOption {
      type = lib.types.str;
      default = "1d";
      description = "How long to keep metrics data";
    };

    email = {
      # Standard SMTP term for the relay that handles outbound mail
      smarthost = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1:1025";
        description = "SMTP smarthost in host:port format";
      };

      from = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Sender email address";
      };

      to = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Recipient email address";
      };
    };
  };

  config = lib.mkIf cfg.enable (let
    allConfigs = inputs.self.nixosConfigurations;

    # Collect watchdog targets from all nixos hosts
    allWatchdogTargets = lib.flatten (
      map (
        name:
          allConfigs.${name}.config.homelab.watchdogTargets or []
      )
      (lib.attrNames allConfigs)
    );

    # Unique hosts that have at least one watchdog target
    watchedHosts = lib.unique (map (t: t.host) allWatchdogTargets);

    # All targets scraped via VPN domain and metrics proxy port
    mkTarget = host: "${host}.${peerDomain}:${metricsPort}";

    # Scrape configs: node exporter for each watched host + each enrolled job
    scrapeConfigs = let
      # Node exporter scrape for each watched host
      nodeScrape = {
        job_name = "node";
        metrics_path = "/metrics/node";
        static_configs =
          map (host: {
            targets = [(mkTarget host)];
            labels = {inherit host;};
          })
          watchedHosts;
      };

      # Group watchdog targets by job name
      targetsByJob = lib.groupBy (t: t.job) allWatchdogTargets;

      # Per-job scrape configs
      jobScrapes =
        lib.mapAttrsToList (jobName: targets: {
          job_name = jobName;
          metrics_path = "/metrics/${jobName}";
          static_configs =
            map (t: {
              targets = [(mkTarget t.host)];
              labels = {host = t.host;};
            })
            targets;
        })
        targetsByJob;
    in
      [nodeScrape] ++ jobScrapes;

    # Auto-generate alerts from watchdog targets
    alertRules = let
      # Per-host node down alert
      hostAlerts =
        map (host: {
          alert = "${host}Down";
          expr = ''up{job="node",host="${host}"} == 0'';
          for = "5m";
          labels = {
            severity = "critical";
            inherit host;
            type = "host";
          };
          annotations.summary = "${host} host is unreachable";
        })
        watchedHosts;

      # Per-service down alert
      serviceAlerts =
        map (t: {
          alert = "${t.host}${lib.strings.toUpper (lib.substring 0 1 t.job) + lib.substring 1 (-1) t.job}Down";
          expr = ''up{job="${t.job}",host="${t.host}"} == 0'';
          for = "5m";
          labels = {
            severity = "critical";
            host = t.host;
            type = "service";
          };
          annotations.summary = "${t.host} ${t.job} is down";
        })
        allWatchdogTargets;
    in
      hostAlerts ++ serviceAlerts;
  in {
    # SMTP password for Protonmail Bridge authentication
    age.secrets.smtp-token = {
      rekeyFile = ../secrets/smtp-token.age;
      owner = "prometheus";
    };

    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [watchdogDomain];

    # Allow HTTPS on VPN interface only
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

    services.prometheus = {
      enable = true;
      port = cfg.port;
      retentionTime = cfg.retention;
      listenAddress = "127.0.0.1";
      extraFlags = ["--web.enable-admin-api"];
      globalConfig.scrape_interval = "30s";
      inherit scrapeConfigs;
      alertmanagers = [
        {
          static_configs = [
            {targets = ["127.0.0.1:${alertmanagerPort}"];}
          ];
        }
      ];
      rules = [
        (builtins.toJSON {
          groups = [
            {
              name = "watchdog";
              rules = alertRules;
            }
          ];
        })
      ];
    };

    # Email-only alertmanager, independent of ntfy
    services.prometheus.alertmanager = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = cfg.alertmanagerPort;
      # Disable clustering since this is a single-node setup.
      # Default cluster port 9094 conflicts with the web listen port.
      extraFlags = ["--cluster.listen-address="];
      configuration = {
        global = {
          smtp_smarthost = cfg.email.smarthost;
          smtp_from = cfg.email.from;
          smtp_auth_username = cfg.email.from;
          smtp_auth_password_file = config.age.secrets.smtp-token.path;
          # Protonmail Bridge on localhost handles TLS upstream
          smtp_require_tls = false;
        };
        route = {
          receiver = "email";
          group_by = ["alertname"];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "12h";
        };
        receivers = [
          {
            name = "email";
            email_configs = [{to = cfg.email.to;}];
          }
        ];
      };
    };

    services.nginx.virtualHosts.${watchdogDomain} = {
      listenAddresses = [cfg.ip];
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${promPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    # Expose watchdog prometheus metrics via unified metrics proxy
    services.nginx.virtualHosts."metrics".locations."/metrics/watchdog".proxyPass = "http://127.0.0.1:${promPort}/metrics";

    homelab.scrapeTargets = [
      {
        job = "watchdog";
        metricsPath = "/metrics/watchdog";
      }
    ];
  });
}

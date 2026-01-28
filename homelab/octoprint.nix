# OctoPrint 3D printer control
#
# - web interface for Prusa printer
# - Obico AI failure detection plugin
# - Prometheus metrics exporter
{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.octoprint;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  serverDomain = "${cfg.subdomain}.${domain}";

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
      default = 5000;
      description = "Port for OctoPrint server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "octoprint";
      description = "Subdomain for OctoPrint";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [serverDomain];

    # Allow HTTPS on VPN interface
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

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
        };
        # Webcam proxy config from webcam module
        locations."/webcam/" = config.homelab.webcam.nginxLocation;
      };
      # OctoPrint metrics via unified metrics proxy
      # Dedicated prometheus user with only PLUGIN_PROMETHEUS_EXPORTER_SCRAPE permission
      # TODO: add setup-octoprint-metrics script to recreate this key if needed
      virtualHosts."metrics".locations."/metrics/octoprint" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}/plugin/prometheus_exporter/metrics";
        extraConfig = ''
          proxy_set_header X-Api-Key "d9_H5XHNOzEtEb50k1NQ4v3iwyfXiSu3QUy9kZ96FFY";
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
  };
}

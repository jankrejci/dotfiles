# OctoPrint 3D printer control with homelab enable flag
{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.octoprint;
  # Prefer homelab namespace, fall back to old options during transition
  services = config.homelab.services or config.serviceConfig;
  host = config.homelab.host or config.hostConfig.self;
  # Use fallback values until homelab namespace is populated by flake
  domain = services.global.domain or "krejci.io";
  serverDomain = "${services.octoprint.subdomain or "octoprint"}.${domain}";

  mkObicoPlugin = ps:
    ps.callPackage ../pkgs/octoprint-obico.nix {};
  mkPrometheusPlugin = ps:
    ps.callPackage ../pkgs/octoprint-prometheus-exporter.nix {};
in {
  options.homelab.octoprint = {
    # Default true preserves existing behavior during transition
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable OctoPrint 3D printer control";
    };
  };

  config = lib.mkIf cfg.enable {
    # Allow HTTPS on VPN interface
    networking.firewall.interfaces."${services.netbird.interface or "nb-homelab"}".allowedTCPPorts = [
      (services.https.port or 443)
    ];

    services.octoprint = {
      enable = true;
      # Listen on localhost only, accessed via nginx proxy
      host = "127.0.0.1";
      port = services.octoprint.port or 5000;
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
      # Localhost proxy for Obico plugin to access webcam via relative URLs
      virtualHosts."localhost" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 80;
          }
        ];
        locations."/webcam/" = {
          proxyPass = "http://${host.services.webcam.ip or "127.0.0.1"}:8080/";
          extraConfig = ''
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };
      };
      virtualHosts.${serverDomain} = {
        listen = [
          {
            addr = host.services.octoprint.ip or "127.0.0.1";
            port = services.https.port or 443;
            ssl = true;
          }
        ];
        onlySSL = true;
        useACMEHost = domain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString (services.octoprint.port or 5000)}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
        # Proxy webcam stream and snapshot from camera-streamer
        locations."/webcam/" = {
          proxyPass = "http://${host.services.webcam.ip or "127.0.0.1"}:8080/";
          # Disable buffering for MJPEG streaming
          extraConfig = ''
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };
      };
      # OctoPrint metrics via unified metrics proxy
      # Dedicated prometheus user with only PLUGIN_PROMETHEUS_EXPORTER_SCRAPE permission
      # TODO: add setup-octoprint-metrics script to recreate this key if needed
      virtualHosts."metrics".locations."/metrics/octoprint" = {
        proxyPass = "http://127.0.0.1:${toString (services.octoprint.port or 5000)}/plugin/prometheus_exporter/metrics";
        extraConfig = ''
          proxy_set_header X-Api-Key "d9_H5XHNOzEtEb50k1NQ4v3iwyfXiSu3QUy9kZ96FFY";
        '';
      };
    };
  };
}

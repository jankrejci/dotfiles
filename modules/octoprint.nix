{
  config,
  lib,
  pkgs,
  ...
}: let
  services = config.serviceConfig;
  domain = "krejci.io";
  serverDomain = "${services.octoprint.subdomain}.${domain}";
  serviceIP = config.hostConfig.self.serviceHosts.octoprint;
  webcamIP = config.hostConfig.self.serviceHosts.webcam;
  httpsPort = 443;

  mkObicoPlugin = ps:
    ps.callPackage ../pkgs/octoprint-obico.nix {};
in {
  # Allow HTTPS on VPN interface
  networking.firewall.interfaces."${services.octoprint.interface}".allowedTCPPorts = [httpsPort];

  services.octoprint = {
    enable = true;
    # Listen on localhost only, accessed via nginx proxy
    host = "127.0.0.1";
    port = services.octoprint.port;
    plugins = ps: [(mkObicoPlugin ps)];
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
        proxyPass = "http://${webcamIP}:8080/";
        extraConfig = ''
          proxy_buffering off;
          proxy_request_buffering off;
        '';
      };
    };
    virtualHosts.${serverDomain} = {
      listenAddresses = [serviceIP];
      forceSSL = true;
      useACMEHost = "${domain}";
      # Only allow access from Netbird VPN network
      extraConfig = ''
        allow 100.76.0.0/16;
        deny all;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString services.octoprint.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
      # Proxy webcam stream and snapshot from camera-streamer
      locations."/webcam/" = {
        proxyPass = "http://${webcamIP}:8080/";
        # Disable buffering for MJPEG streaming
        extraConfig = ''
          proxy_buffering off;
          proxy_request_buffering off;
        '';
      };
    };
  };
}

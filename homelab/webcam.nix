# Webcam streaming service for camera-streamer
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.webcam;
  camera-streamer = pkgs.callPackage ../pkgs/camera-streamer.nix {};
  port = 8080;
in {
  options.homelab.webcam = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable webcam streaming via camera-streamer";
    };

    # Nginx location config for other modules to include in their vhosts
    nginxLocation = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "Nginx location config for proxying to camera-streamer";
    };
  };

  config = lib.mkIf cfg.enable {
    # Expose nginx location config for other modules
    homelab.webcam.nginxLocation = {
      proxyPass = "http://127.0.0.1:${toString port}/";
      extraConfig = ''
        proxy_buffering off;
        proxy_request_buffering off;
      '';
    };

    # Camera tools for testing and streaming
    environment.systemPackages = [
      pkgs.libcamera
      camera-streamer
    ];

    # Camera streaming service
    systemd.services.camera-streamer = {
      description = "Camera Streamer";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      # Only start if a camera is actually connected
      unitConfig.ConditionPathExists = "/dev/video0";
      serviceConfig = {
        # OV5647 native 4:3 binned mode to avoid cropping.
        # Saturation=0 produces grayscale output for better IR night vision.
        ExecStart = builtins.concatStringsSep " " [
          "${camera-streamer}/bin/camera-streamer"
          "--camera-type=libcamera"
          "--camera-width=1920"
          "--camera-height=1440"
          "--camera-fps=5"
          "--camera-options=Saturation=0"
          "--http-port=${toString port}"
          "--http-listen=127.0.0.1"
        ];
        Restart = "on-failure";
        RestartSec = "10s";
        # Run as root to access camera devices
        User = "root";
        Group = "video";
      };
    };

    # Localhost proxy for services that need webcam via relative URLs.
    # Used by Obico plugin to access webcam at http://localhost/webcam/
    services.nginx = {
      enable = true;
      virtualHosts."localhost" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 80;
          }
        ];
        locations."/webcam/" = config.homelab.webcam.nginxLocation;
      };
    };
  };
}

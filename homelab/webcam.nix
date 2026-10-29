# Webcam streaming via camera-streamer
#
# - MJPEG streaming on port 8080
# - libcamera backend for RPi camera
# - used by OctoPrint for print monitoring
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.webcam;
  # Taken from unstable since stable does not carry it yet, and used as
  # unstable builds it so the whole camera stack comes from cache.nixos.org.
  # Swapping in the host libcamera and ffmpeg forced a local build of the
  # raspberrypi ffmpeg fork under emulation. Nothing else on the host uses
  # either library, and the vc4 pipeline handler the Pi camera needs is in
  # upstream libcamera.
  camera-streamer = pkgs.unstable.camera-streamer;
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

    # Camera tools for testing and streaming. The libcamera tools come from
    # the same set as camera-streamer, so a test with `cam` exercises the
    # library version the streamer runs.
    environment.systemPackages = [
      pkgs.unstable.libcamera
      camera-streamer
    ];

    # Camera streaming service
    systemd.services.camera-streamer = {
      description = "Camera Streamer";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      # Only start if a camera is actually connected.
      #
      # Give up after a handful of failures instead of retrying forever. A
      # camera that aborts on every start is worse than a dead camera, because
      # each abort writes a core several times the process peak, which
      # systemd-coredump then reads back and compresses. On a board with
      # little RAM to spare that loop took the whole host down twice,
      # where a failed unit is visible and costs nothing.
      unitConfig = {
        ConditionPathExists = "/dev/video0";
        StartLimitIntervalSec = "5min";
        StartLimitBurst = 5;
      };
      serviceConfig = {
        # OV5647 native 4:3 binned mode to avoid cropping.
        # Saturation=0 produces grayscale output for better IR night vision.
        #
        # The H264 path is off because the VideoCore encoder refuses to start
        # on this board. bcm2835-codec reports "Failed enabling i/p port, ret
        # -3" on every attempt, camera-streamer then tears the pipeline down,
        # and libcamera aborts in that teardown, which is what crashed the
        # service. The JPEG path starts fine on the same run, and OctoPrint
        # only ever reads /webcam/stream and /webcam/snapshot, so nothing
        # consumes H264 anyway.
        ExecStart = builtins.concatStringsSep " " [
          "${camera-streamer}/bin/camera-streamer"
          "--camera-type=libcamera"
          "--camera-width=1920"
          "--camera-height=1440"
          "--camera-fps=5"
          "--camera-options=Saturation=0"
          "--camera-video.disabled=1"
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

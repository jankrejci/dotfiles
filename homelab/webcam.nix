# Webcam streaming via camera-streamer
#
# - hardware H.264 over WebRTC
# - libcamera backend for RPi camera
# - served to the VPN over HTTPS on the host's peer name for viewing
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
  services = config.homelab.services;
  peerName = config.homelab.host.peerName;
in {
  options.homelab.webcam = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable webcam streaming via camera-streamer";
    };

    port.streamer = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port camera-streamer listens on at localhost";
    };

    # A tile needs both a name and an icon, so they are set together or not
    # at all.
    dashboard = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Dashboard tile name for the camera";
          };

          icon = lib.mkOption {
            type = lib.types.path;
            description = "Dashboard tile icon";
          };
        };
      });
      default = null;
      description = "Dashboard tile for the camera, no tile when null";
    };

    # The stream paths belong to camera-streamer, so consumers on other hosts
    # read the URL here instead of knowing them.
    url.video = lib.mkOption {
      type = lib.types.str;
      default = "https://${peerName}/video.mkv";
      readOnly = true;
      description = "URL of the H.264 stream in Matroska served to the VPN";
    };
  };

  config = lib.mkIf cfg.enable {
    # The vhost takes the host certificate, so the host has to issue it.
    homelab.acme.hostCert = true;

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
        # The OV5647 binned 1296x972 mode keeps the full 4:3 field of view at
        # 25 fps and stays under the 1080p limit of the VideoCore H.264
        # encoder, which failed with "Failed enabling i/p port, ret -3" on
        # larger frames. The full-sensor mode only reaches 15 fps and the
        # 1920x1080 mode is a center crop.
        #
        # The ISP scales the H.264 output to 1024x768, which keeps that full
        # view while lowering the bitrate the Obico stream relays. The
        # rescaler aligns its output, so 960x720 came out as 992x736 and
        # stretched the picture, while 1024x768 is exact 4:3.
        #
        # The infrared LED boards on the Waveshare RPi Camera (F) disturb the
        # sensor while they are lit, which shows as rows of stripes in every
        # mode and as a white frame in this one. Daylight frames are clean, so
        # the fix is on the LED power side, not here.
        #
        # Snapshots and MJPEG from the JPEG encoder are broken. The WebRTC page
        # at /webrtc is the view for people, and prusa-obico cuts the Obico
        # snapshots from the H.264 stream at /video.mkv instead.
        # Saturation=0 produces grayscale output for better IR night vision.
        # AeFlickerPeriod matches exposure to 50Hz mains lighting.
        #
        # Every WebRTC browser must decode Constrained Baseline, but not every one
        # takes High profile, and a browser that rejects the only video m-line
        # fails the whole Obico live stream. Level 3.1 covers 1024x768 at 25 fps
        # with room to spare, 76800 macroblocks a second against a limit of
        # 108000. Menu values match on their label first, so the level is the
        # label "3.1" and the profile the label "Constrained Baseline" with the
        # spaces dropped. The options append to the defaults, so these win.
        ExecStart = builtins.concatStringsSep " " [
          "${camera-streamer}/bin/camera-streamer"
          "--camera-type=libcamera"
          "--camera-width=1296"
          "--camera-height=972"
          "--camera-fps=25"
          "--camera-video.height=768"
          "--camera-video.options=video_bitrate=2000000"
          "--camera-video.options=h264_profile=ConstrainedBaseline"
          "--camera-video.options=h264_level=3.1"
          "--camera-options=Saturation=0"
          "--camera-options=AeFlickerMode=1"
          "--camera-options=AeFlickerPeriod=10000"
          "--http-port=${toString cfg.port.streamer}"
          "--http-listen=127.0.0.1"
        ];
        # The camera has no infrared filter, so the default ov5647 tuning
        # misjudges its colour and exposure. The NoIR tuning ships with the
        # same libcamera camera-streamer is built against.
        Environment = "LIBCAMERA_RPI_TUNING_FILE=${pkgs.unstable.libcamera}/share/libcamera/ipa/rpi/vc4/ov5647_noir.json";
        Restart = "on-failure";
        RestartSec = "10s";
        # With video on, camera-streamer hangs in libcamera teardown and
        # ignores SIGTERM, so give it a few seconds before SIGKILL instead of
        # holding up every restart for the default 90.
        TimeoutStopSec = "5s";
        # Run as root to access camera devices
        User = "root";
        Group = "video";
      };
    };

    services.nginx = {
      enable = true;
      # The camera is served to the VPN without SSO, the same way the metrics
      # vhost is, because the VPN is the access boundary for both. The
      # Obico bridge on another host takes its snapshots and live stream from
      # here and people watch the WebRTC page at /webrtc. The peer name
      # resolves for every VPN client and has its own certificate, so HTTPS
      # needs no service IP or DNS record, and onlySSL keeps port 80 closed.
      #
      # The vhost sets no listenAddresses, so blackbox-exporter, which probes
      # only vhosts that have them, does not probe this certificate. Renewal
      # failures are covered by the AcmeFailed alert.
      virtualHosts.${peerName} = {
        onlySSL = true;
        useACMEHost = peerName;
        extraConfig = ''
          allow ${services.netbird.subnet};
          deny all;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port.streamer}/";
          extraConfig = ''
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };
      };
    };

    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [services.https.port];

    # The tile opens the WebRTC page because the camera JPEG snapshots and
    # MJPEG are broken. Hosts that set no tile get none.
    homelab.dashboardEntries = lib.optional (cfg.dashboard != null) {
      inherit (cfg.dashboard) name icon;
      url = "https://${peerName}/webrtc";
    };
  };
}

{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  camera-streamer = pkgs.callPackage ../pkgs/camera-streamer.nix {};
in {
  # RPi Zero 2 W with OctoPrint and camera streaming.
  # Note: deploy-rs may fail due to nix daemon crashes on this device.
  # Manual workaround: nix copy + ssh activate directly.
  imports = [inputs.nixos-raspberrypi.nixosModules.raspberry-pi-02.base];

  # SD card stability on Zero 2 W
  boot.kernelParams = ["sdhci.debug_quirks2=4"];

  # BCM43430 WiFi stability fixes for Zero 2 W:
  # - roamoff=1: disable firmware roaming which causes connection drops
  # - txglomsz=8: reduce SDIO packet aggregation to prevent bus stress
  boot.extraModprobeConfig = ''
    options brcmfmac roamoff=1 txglomsz=8
  '';

  # Boost core voltage to improve WiFi SDIO stability under sustained load.
  # BCM43430 can crash when transmitting at high power with marginal voltage.
  hardware.raspberry-pi.extra-config = lib.mkAfter ''
    over_voltage=2
  '';

  # Allow OctoPrint to access serial port ttyAMA0, vcgencmd for throttling, and camera
  users.users.octoprint.extraGroups = ["dialout" "video"];

  # Allow admin to access camera devices for testing
  users.users.admin.extraGroups = ["video"];

  # Camera tools for testing and streaming
  environment.systemPackages = [
    pkgs.libcamera
    camera-streamer
  ];

  # Camera streaming service for OctoPrint integration
  systemd.services.camera-streamer = {
    description = "Camera Streamer for Prusa";
    after = ["network.target" "sys-subsystem-net-devices-services.device"];
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
        "--http-port=8080"
        "--http-listen=${config.homelab.octoprint.webcamIp}"
      ];
      Restart = "on-failure";
      RestartSec = "10s";
      # Run as root to access camera devices
      User = "root";
      Group = "video";
    };
  };
}

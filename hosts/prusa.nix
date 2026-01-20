{
  config,
  inputs,
  lib,
  ...
}: {
  homelab.alerts.hosts = [
    {
      alert = "prusa-down";
      expr = ''up{instance=~"prusa.*", job="node"} == 0'';
      labels = {
        severity = "critical";
        host = config.homelab.host.hostName;
        type = "host";
        oneshot = "true";
      };
      annotations.summary = "prusa host is down";
    }
  ];

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
}

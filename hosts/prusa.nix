# Raspberry Pi Zero 2 W with OctoPrint and camera
#
# - WiFi stability fixes for BCM43430
# - WiFi ingress bandwidth limit to prevent crashes during deploys
# - over_voltage for SDIO stability
# - OctoPrint serial port and camera access
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  homelab.alerts.hosts = [
    {
      alert = "PrusaDown";
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

  # Limit incoming WiFi bandwidth to prevent BCM43430 firmware crashes under
  # sustained load from deploys. Ingress policing drops excess packets, causing
  # TCP to back off to a sustainable rate for the Zero 2 W WiFi chip.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", ENV{DEVTYPE}=="wlan", TAG+="systemd", ENV{SYSTEMD_WANTS}="wifi-ingress-limit@%k.service"
  '';

  systemd.services."wifi-ingress-limit@" = {
    description = "WiFi ingress bandwidth limit for %i";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.iproute2}/bin/tc qdisc add dev %i handle ffff: ingress"
        "${pkgs.iproute2}/bin/tc filter add dev %i parent ffff: protocol all u32 match u32 0 0 police rate 4mbit burst 128k drop flowid :1"
      ];
      ExecStop = "${pkgs.iproute2}/bin/tc qdisc del dev %i handle ffff: ingress";
    };
  };

  # Allow OctoPrint to access serial port ttyAMA0, vcgencmd for throttling, and camera
  users.users.octoprint.extraGroups = ["dialout" "video"];

  # Allow admin to access camera devices for testing
  users.users.admin.extraGroups = ["video"];
}

{inputs, ...}: {
  imports = [inputs.nixos-raspberrypi.nixosModules.raspberry-pi-02.base];

  # SD card stability on Zero 2 W
  boot.kernelParams = ["sdhci.debug_quirks2=4"];

  # Allow OctoPrint to access serial port ttyAMA0 and vcgencmd for throttling checks
  users.users.octoprint.extraGroups = ["dialout" "video"];
}

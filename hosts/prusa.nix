{inputs, ...}: {
  imports = [inputs.nixos-raspberrypi.nixosModules.raspberry-pi-02.base];

  # SD card stability on Zero 2 W
  boot.kernelParams = ["sdhci.debug_quirks2=4"];

  # Prevent Bluetooth UART driver from claiming ttyAMA0
  boot.blacklistedKernelModules = ["hci_uart"];

  # Disable Bluetooth via config.txt overlay to free ttyAMA0 for printer serial port.
  hardware.raspberry-pi.config.all.dt-overlays.disable-bt = {
    enable = true;
    params = {};
  };

  # Allow OctoPrint to access serial port ttyAMA0 and vcgencmd for throttling checks
  users.users.octoprint.extraGroups = ["dialout" "video"];
}

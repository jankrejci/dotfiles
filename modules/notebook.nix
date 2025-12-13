{pkgs, ...}: {
  # Device driver packages
  hardware.firmware = with pkgs; [
    linux-firmware
  ];

  # For better hardware compatibility
  hardware.enableAllFirmware = true;
  # Enable non-free firmware
  hardware.enableRedistributableFirmware = true;

  # Allow applications to update firmware
  services.fwupd.enable = true;

  # Enable hardware accelerated graphic drivers
  hardware.graphics.enable = true;

  # Enable temperature management daemon
  services.thermald.enable = true;
  # Enable powertop autotuning (complements power-profiles-daemon)
  powerManagement.powertop.enable = true;

  hardware.bluetooth.enable = true;
  # GNOME has built-in bluetooth support, blueman not needed

  # Enable fingerprint reader (if available on your model)
  services.fprintd.enable = true;

  # Disable autosuspend of selected USB peripherals
  services.udev.extraRules = ''
    # Disable autosuspend for mouse devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{product}=="*[Mm]ouse*", ATTR{power/autosuspend}="-1"
    # Disable autosuspend for keyboard devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{product}=="*[Kk]eyboard*", ATTR{power/autosuspend}="-1"
    # Disable autosuspend for Logitech Unifying Receivers (wireless mice/keyboards)
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="046d", ATTR{idProduct}=="c52b", ATTR{power/autosuspend}="-1"
    # Disable autosuspend for USB Receiver devices (generic wireless receivers)
    ACTION=="add", SUBSYSTEM=="usb", ATTR{product}=="*[Rr]eceiver*", ATTR{power/autosuspend}="-1"
  '';
}

{pkgs, ...}: {
  # Device driver packages
  hardware.firmware = with pkgs; [
    linux-firmware
    firmwareLinuxNonfree
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
  # Enable powertop autotuning
  powerManagement.powertop.enable = true;

  hardware.bluetooth.enable = true;
  # Optional Bluetooth manager
  services.blueman.enable = true;

  # Enable fingerprint reader (if available on your model)
  services.fprintd.enable = true;

  # Disable autosuspend of selected USB peripherals
  services.udev.extraRules = ''
    # Disable autosuspend for mouse devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{product}=="*[Mm]ouse*", ATTR{power/autosuspend}="-1"
    # Disable autosuspend for keyboard devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{product}=="*[Kk]eyboard*", ATTR{power/autosuspend}="-1"
  '';
}

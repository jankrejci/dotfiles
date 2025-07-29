{pkgs, ...}: {
  # Enable ThinkPad ACPI support for ThinkPad features
  hardware.trackpoint = {
    enable = true;
    sensitivity = 255;
    speed = 120;
  };

  services.thermald.enable = true;
  powerManagement.powertop.enable = true;

  # For better hardware compatibility
  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Enable non-free firmware
  hardware.enableRedistributableFirmware = true;

  # ThinkPad E470 keyboard backlight
  hardware.acpilight.enable = true;

  # Graphics - E470 typically has Intel HD Graphics 620
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      libvdpau-va-gl
    ];
  };

  # Add support for the fingerprint reader
  services.fprintd.enable = true;

  # Wireless drivers support - the E470 uses Intel wireless cards
  hardware.firmware = with pkgs; [
    linux-firmware
    firmwareLinuxNonfree
  ];

  # Sleep/hibernation optimization
  boot.kernelParams = [
    "mem_sleep_default=deep"
  ];

  # Configure power button behavior
  services.logind = {
    lidSwitch = "suspend";
    extraConfig = ''
      HandlePowerKey=suspend
    '';
  };
}

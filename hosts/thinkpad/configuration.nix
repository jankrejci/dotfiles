{ pkgs, ... }:
{
  services.tlp = {
    enable = true;
    settings = {
      # ThinkPad-specific TLP settings
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;

      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

      # For better battery life on ThinkPads
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";

      # ThinkPad-specific settings
      DEVICES_TO_DISABLE_ON_STARTUP = "bluetooth";
      DEVICES_TO_ENABLE_ON_STARTUP = "wifi";
    };
  };

  # Enable ThinkPad ACPI support for ThinkPad features
  hardware.trackpoint = {
    enable = true;
    sensitivity = 255;
    speed = 120;
  };

  # For ThinkPad power management 
  services.thermald.enable = true;
  powerManagement.powertop.enable = true;

  # For better hardware compatibility
  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # ThinkPad E470 keyboard backlight
  hardware.acpilight.enable = true;

  # Graphics - E470 typically has Intel HD Graphics 620
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      libvdpau-va-gl
    ];
  };

  # Add support for the fingerprint reader (if your model has one)
  services.fprintd.enable = true;

  # Wireless drivers support - the E470 uses Intel wireless cards
  hardware.firmware = with pkgs; [
    firmwareLinuxNonfree
    intel-firmware
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

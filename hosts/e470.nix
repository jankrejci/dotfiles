{
  config,
  pkgs,
  ...
}: {
  # Enable ThinkPad ACPI support for ThinkPad features
  hardware.trackpoint = {
    enable = true;
    sensitivity = 255;
    speed = 120;
  };

  hardware.cpu.intel.updateMicrocode = true;

  # ThinkPad-specific kernel modules for ACPI features and power management
  boot.initrd.availableKernelModules = ["thinkpad_acpi" "rtsx_pci_sdmmc"];
  boot.initrd.kernelModules = ["acpi_call"];
  boot.extraModulePackages = with config.boot.kernelPackages; [acpi_call];

  # ThinkPad E470 keyboard backlight
  hardware.acpilight.enable = true;

  # Graphics - E470 typically has Intel HD Graphics 620
  hardware.graphics = {
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      libvdpau-va-gl
    ];
  };

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

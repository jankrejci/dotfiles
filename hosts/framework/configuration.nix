{ pkgs, ... }:
{
  boot = {
    kernelModules = [ "kvm-amd" ];
    # Better support for sleep states
    kernelParams = [
      "mem_sleep_default=deep"
      # More stable performance for AMD models (if applicable)
      # "amd_pstate=active"
    ];
  };

  services.fwupd.enable = true;
  hardware.cpu.amd.updateMicrocode = true;

  # Enable fingerprint reader (if available on your model)
  services.fprintd.enable = true;

  services.thermald.enable = true;
  powerManagement.powertop.enable = true;

  # Enable non-free firmware
  hardware.enableRedistributableFirmware = true;

  # Add specific firmware packages
  hardware.firmware = with pkgs; [
    linux-firmware
    firmwareLinuxNonfree
  ];

  # For AMD GPU support
  hardware.graphics.enable = true;

  # For Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true; # Optional Bluetooth manager
}

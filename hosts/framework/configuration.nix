{ config, ... }:
{
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = config.hardware.enableRedistributableFirmware;

  hardware.framework.laptop = {
    enable = true;
    amd.enable = true; # If you have an AMD model
  };
}

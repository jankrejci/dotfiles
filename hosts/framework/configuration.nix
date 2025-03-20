{ config, ... }:
{
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = config.hardware.enableRedistributableFirmware;
}

{ config, lib, ... }:
{
  disko.devices.disk.main.device = "/dev/nvme0n1";
  boot.kernelModules = [ "kvm-amd" ];

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

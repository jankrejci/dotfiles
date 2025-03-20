{ config, ... }:
{
  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
}

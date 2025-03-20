{ config, lib, ... }:
{
  boot.initrd.luks.devices."luks-4146767d-b4f4-4a2e-be33-f12e11165724".device = "/dev/disk/by-uuid/4146767d-b4f4-4a2e-be33-f12e11165724";
  boot.initrd.luks.devices."luks-6f20f78f-8a23-4f07-8726-67fa1da4c5b7".device = "/dev/disk/by-uuid/6f20f78f-8a23-4f07-8726-67fa1da4c5b7";

  boot.kernelModules = [ "kvm-intel" ];

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/ad493dc4-5a52-4061-9b0a-4fadaf6c9cf2";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/B578-83EA";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
  };

  swapDevices = [{ device = "/dev/disk/by-uuid/e0b1e797-4887-4e3c-a020-c7c506bcfa52"; }];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

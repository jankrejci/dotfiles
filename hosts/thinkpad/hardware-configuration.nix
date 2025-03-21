# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "sd_mod" "sdhci_pci" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/8de3a526-2ed8-48a2-9f8d-77b94f72ce5d";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."luks-cef66a91-adcd-47a5-b0a4-3982d212ef2e".device = "/dev/disk/by-uuid/cef66a91-adcd-47a5-b0a4-3982d212ef2e";

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/034E-515C";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  swapDevices =
    [{ device = "/dev/disk/by-uuid/e94518b7-fcb7-4326-93b9-379c4d83ca9d"; }];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

{ ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-c2bd7e97-dd43-4663-9c86-ab3a1ae3a822".device = "/dev/disk/by-uuid/c2bd7e97-dd43-4663-9c86-ab3a1ae3a822";
}

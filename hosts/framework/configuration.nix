{ ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  disko.devices.disk.main.device = "/dev/nvme0n1";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}

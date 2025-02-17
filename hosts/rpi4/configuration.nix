{ pkgs, lib, ... }:
{
  security.sudo.wheelNeedsPassword = false;

  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcPS15FwxQjt4xZJk0+VzKqLTh/rikF0ZI4GFyOTLoD jkr@optiplex-rpi4"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwuE1yPiKiX7SL1mSDZB6os9COPdOqrWfh9rUNBpfOq jkr@thinkpad-rpi4"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqz14JAcEgnxuy4xIkUiots+K1bo1uQGd/Tn7mRWyu+ jkr@latitude-rpi4"
    ];
  };

  nix.settings.trusted-public-keys = [
    "jkr-prusa:mfZZpEV+n0c0Pe4dTJyLSnNz6oQO2Kx86S3RcG9mwXk="
  ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;

  hardware = {
    enableRedistributableFirmware = lib.mkForce false;
    firmware = [ pkgs.raspberrypiWirelessFirmware ];
  };

  boot.initrd.availableKernelModules = [ "xhci_pci" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=CZ
  '';

  networking.supplicant.wlan0 = {
    driver = "nl80211";
    configFile.path = "/etc/wpa_supplicant.conf";
  };

  swapDevices = [ ];

  sdImage = {
    compressImage = false;
    imageName = "rpi4.img";
  };

  services.avahi.enable = false;
  services.nfs.server.enable = false;
  services.samba.enable = false;
  networking.networkmanager.enable = false;
  # Disable unneeded features
  hardware.bluetooth.enable = false;
  services.journald.extraConfig = "Storage=volatile";

  networking.useDHCP = lib.mkForce false;

  networking.interfaces.end0.useDHCP = true;
  networking.interfaces.wlan0.useDHCP = true;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  systemd.services."first-boot-reboot" = {
    description = "Reboot after first boot initialization";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionFirstBoot = true;
    script = ''
      echo "First boot detected. Rebooting system."
      systemctl reboot
    '';
  };
}


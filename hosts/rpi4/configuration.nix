{ config, lib, ... }:
{
  security.sudo.wheelNeedsPassword = false;

  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcPS15FwxQjt4xZJk0+VzKqLTh/rikF0ZI4GFyOTLoD jkr@optiplex-rpi4"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwuE1yPiKiX7SL1mSDZB6os9COPdOqrWfh9rUNBpfOq jkr@thinkpad-rpi4"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqz14JAcEgnxuy4xIkUiots+K1bo1uQGd/Tn7mRWyu+ jkr@latitude-rpi4"
    ];
  };

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  swapDevices = [ ];

  networking.useDHCP = lib.mkForce false;

  networking.interfaces.end0.useDHCP = true;
  networking.interfaces.wlan0.useDHCP = true;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  sops = {
    secrets = {
      wifi = {
        sopsFile = ../../wifi.env;
        format = "dotenv";
        owner = "root";
        group = "systemd-networkd";
        mode = "0400";
      };
    };
  };

  networking.wireless = {
    enable = true;
    secretsFile = config.sops.secrets.wifi.path;
    networks = {
      "ext:home_ssid" = {
        pskRaw = "ext:home_psk";
      };
    };
  };
}


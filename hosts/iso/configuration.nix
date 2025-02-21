{ lib, ... }:
{
  boot = {
    supportedFilesystems = lib.mkForce [ "vfat" "f2fs" "xfs" "ntfs" "cifs" ];
    loader.efi.canTouchEfiVariables = true;
  };

  systemd.network.networks = {
    "10-all-ethernet" = {
      matchConfig.Type = "ether";
      DHCP = "yes";
    };

    "10-all-wifi" = {
      matchConfig.Type = "wlan";
      DHCP = "yes";
    };
  };

  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBsvOywMRwMnEqlKobDF1F1ZrEJNGj0kIHPZAmvVmZbG jkr@optiplex-iso"
    ];
  };

  isoImage.compressImage = false;
}


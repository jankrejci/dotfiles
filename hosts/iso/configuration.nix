{ lib, ... }:
{
  fileSystems."/boot".options = [ "umask=0077" ]; # Removes permissions and security warnings.

  boot = {
    supportedFilesystems = lib.mkForce [ "vfat" "f2fs" "xfs" "ntfs" "cifs" ];
    kernelParams = [
      # "systemd.setenv=SYSTEMD_SULOGIN_FORCE=1"
      # "systemd.show_status=true"
      #"systemd.log_level=debug"
      # "systemd.log_target=console"
      # "systemd.journald.forward_to_console=1"
    ];
  };

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot = {
      enable = true;
      # Pick the highest resolution for systemd-boot's console.
      consoleMode = lib.mkDefault "max";
    };
  };

  # boot.initrd = {
  #   systemd.enable = true;
  #   systemd.emergencyAccess = true; # Don't need to enter password in emergency mode
  #   luks.forceLuksSupportInInitrd = true;
  # };

  # Avoid collision with systemd networking
  networking.useDHCP = lib.mkForce false;

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


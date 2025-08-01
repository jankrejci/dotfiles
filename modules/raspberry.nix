{
  lib,
  pkgs,
  ...
}: {
  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  # Override the default platform
  nixpkgs.hostPlatform = "aarch64-linux";

  hardware = {
    enableRedistributableFirmware = true;
    firmware = [pkgs.raspberrypiWirelessFirmware];
  };

  boot = {
    kernelModules = [];
    loader = {
      # Use the extlinux boot loader. NixOS wants to enable GRUB by default.
      grub.enable = false;
      # Enables the generation of /boot/extlinux/extlinux.conf
      generic-extlinux-compatible.enable = true;
    };
    # Define propper wifi channels
    # This workaroud seems too be no longer needed for proper wifi function on rpi02w
    # options brcmfmac roamoff=1 feature_disable=0x82000
    extraModprobeConfig = lib.mkDefault ''
      options cfg80211 ieee80211_regdom=CZ
    '';
    supportedFilesystems = {zfs = lib.mkForce false;};
  };

  # Override sd-card module configuration
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS-SD";
      fsType = "ext4";
    };
  };
  swapDevices = [];

  # TODO find out more unused services to disable
  # Disable unneeded features
  services = {
    avahi.enable = false;
    nfs.server.enable = false;
    samba.enable = false;
    journald.extraConfig = "Storage=volatile";
  };

  # TODO Turn off BT properly, it still emmits some errors
  # I dont need the bluetooth so far
  hardware.bluetooth.enable = false;
}

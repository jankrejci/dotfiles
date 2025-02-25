{ ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}

{ ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN85SndW/OerKK8u2wTxmHcTn4hEtUJmctj9wnseBYtS jkr@optiplex-vpsfree"
    ];
  };

  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  disko.devices.disk.main.device = "/dev/sda";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}

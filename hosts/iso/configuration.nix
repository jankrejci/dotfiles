{ lib, ... }:
{
  boot = {
    loader.efi.canTouchEfiVariables = true;
  };

  # TODO use the ssh-authorized-keys.pub file instead
  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBsvOywMRwMnEqlKobDF1F1ZrEJNGj0kIHPZAmvVmZbG jkr@optiplex-iso"
    ];
  };

  isoImage.compressImage = false;

  # Allow nixos-anywhere to login as root for installation
  services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
}


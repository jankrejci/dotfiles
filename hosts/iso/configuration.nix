{ lib, ... }:
{
  boot = {
    loader.efi.canTouchEfiVariables = true;
  };

  isoImage.compressImage = false;

  # Allow nixos-anywhere to login as root for installation
  services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
}


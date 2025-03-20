{ lib, ... }:
{
  boot = {
    loader.efi.canTouchEfiVariables = true;
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-partlabel/nixos-minimal-24.11-x86_64";
      fsType = "ext4";
    };
  };

  # Allow nixos-anywhere to login as root for installation
  services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
}


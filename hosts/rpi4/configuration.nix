{ pkgs, lib, hostConfig, ... }:
let
  # Import the key file
  adminKeyFilePath = builtins.toFile "keys.txt" (builtins.readFile "/home/jkr/.config/sops/age/keys.txt");

  # Copy the key into a derivation
  adminKeyFile = pkgs.runCommand "age-key.txt" { } ''
    mkdir -p $out
    cp ${adminKeyFilePath} $out/keys.txt
  '';

  # Decrypt the secrets using the correct path
  decryptedSecret = pkgs.runCommand "decrypted-secret" { buildInputs = [ pkgs.sops ]; } ''
    export SOPS_AGE_KEY_FILE=${adminKeyFile}/keys.txt
    mkdir -p $out
    sops --decrypt --extract '["hosts"]["${hostConfig.hostName}"]["sops_private_key"]' ${../../secrets.yaml} > $out/keys.txt
  '';
in
{
  # imports = [
  #   ./hardware-configuration.nix
  # ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;

  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcPS15FwxQjt4xZJk0+VzKqLTh/rikF0ZI4GFyOTLoD jkr@optiplex-rpi4"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwuE1yPiKiX7SL1mSDZB6os9COPdOqrWfh9rUNBpfOq jkr@thinkpad-rpi4"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqz14JAcEgnxuy4xIkUiots+K1bo1uQGd/Tn7mRWyu+ jkr@latitude-rpi4"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  boot.initrd.availableKernelModules = [ "xhci_pci" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.end0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlan0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";


  # Ensure the key is stored in the correct location
  environment.etc."sops/age/keys.txt".source = "${decryptedSecret}/keys.txt";
}


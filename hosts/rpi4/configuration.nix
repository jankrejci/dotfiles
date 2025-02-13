{ config, pkgs, lib, hostConfig, ... }:
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
  # Ensure the key is stored in the correct location
  environment.etc."sops/age/keys.txt".source = "${decryptedSecret}/keys.txt";

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


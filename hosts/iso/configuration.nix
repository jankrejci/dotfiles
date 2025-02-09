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
  # Ensure the key is stored in the correct location
  environment.etc."sops/age/keys.txt".source = "${decryptedSecret}/keys.txt";

  fileSystems."/boot".options = [ "umask=0077" ]; # Removes permissions and security warnings.

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    supportedFilesystems = lib.mkForce [ "btrfs" "reiserfs" "vfat" "f2fs" "xfs" "ntfs" "cifs" ];
    kernelParams = [
      "systemd.setenv=SYSTEMD_SULOGIN_FORCE=1"
      "systemd.show_status=true"
      #"systemd.log_level=debug"
      "systemd.log_target=console"
      "systemd.journald.forward_to_console=1"
    ];
  };

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot = {
      enable = true;
      # We use Git for version control, so we don't need to keep too many generations.
      configurationLimit = lib.mkDefault 2;
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

  # The default compression-level is (6) and takes too long on some machines (>30m). 3 takes <2m
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";

  services.qemuGuest.enable = true;
}


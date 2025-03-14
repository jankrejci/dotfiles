{ config, lib, pkgs, ... }:
{
  # Access to all raspberry hosts without sudo for convenience
  security.sudo.wheelNeedsPassword = false;

  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "jkr@optiplex:KwH9qv7qCHd+npxC0FUFCApM1rP6GSbB8Ze983CCT8o="
  ];

  boot = {
    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "usbhid"
      "usb_storage"
      "sd_mod"
    ];
    kernelModules = [
      "kvm-intel"
      "tpm_tis"
      "tpm_crb"
    ];
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 3;
        # Disable boot menu editing
        editor = false;
      };
      efi.canTouchEfiVariables = true;
    };
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  environment.systemPackages = with pkgs; [
    sbctl
  ];

  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-partlabel/disk-main-luks";
    preLVM = true;
    allowDiscards = true;
    # bypassWorkqueues = true; # Improves unlocking performance
  };

  boot.initrd.systemd = {
    enable = true;
    tpm2.enable = true;
  };

  boot.initrd.systemd.services."tpm-delay" = {
    description = "Delay before TPM decryption";
    wantedBy = [ "systemd-cryptsetup@cryptroot.service" ];
    before = [ "systemd-cryptsetup@cryptroot.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/sleep 5";
    };
  };

  # TPM unlocking
  security.tpm2 = {
    enable = true;
    tctiEnvironment.enable = true; # Sets up TPM environment variables
  };
}

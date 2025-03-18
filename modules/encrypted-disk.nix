{ config, lib, pkgs, ... }:
let
  luksDevice = "/dev/disk/by-partlabel/disk-main-luks";
  diskPasswordFile = "/var/lib/disk-password";
in
{
  # Boot parition and encrypted root partition
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = config.hosts.self.device;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                extraOpenArgs = [ ];
                passwordFile = diskPasswordFile;
                content = {
                  type = "lvm_pv";
                  vg = "pool";
                };
              };
            };
          };
        };
      };
    };
    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [
                "defaults"
              ];
            };
          };
          swap = {
            size = lib.mkDefault "1G";
            content = {
              type = "swap";
              discardPolicy = "both";
            };
          };
        };
      };
    };
  };

  boot = {
    # Add TPM support modules
    kernelModules = [
      "tpm_tis"
      "tpm_crb"
    ];
    loader = {
      systemd-boot = {
        # Systemd boot instead of GRUB is needed for secure boot,
        # to use secure boot with GRUB, you need to use Lanzaboote project
        enable = true;
        # Avoid too many bootloader generations
        # that can consume all the /boot partition space
        configurationLimit = 3;
        # Disable boot menu editing
        editor = false;
      };
      efi.canTouchEfiVariables = true;
    };
  };

  # Encryption tools needed for TPM and secure boot
  environment.systemPackages = with pkgs; [
    sbctl
    tpm2-tools
    clevis
  ];

  # To use TPM stored key for disk encryption, wipe the luks tmp slot first
  # `systemd-cryptenroll --wipe-slot=tpm2 ${luksDevice}`
  # and then enroll new key
  # `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,7 /dev/sda`
  # It is good practice to still have a manual password to recover partition
  # if TMP approach fails
  boot.initrd.luks.devices."cryptroot" = {
    device = luksDevice;
    preLVM = true;
    allowDiscards = true;
  };

  # Enable TMP support
  security.tpm2.enable = true;
  boot.initrd.systemd = {
    enable = true;
    tpm2.enable = true;
  };

  # Workaround to add delay to avoid TPM unlock timing issues
  boot.initrd.systemd.services."tpm-delay" = {
    description = "Delay before TPM decryption";
    wantedBy = [ "systemd-cryptsetup@cryptroot.service" ];
    before = [ "systemd-cryptsetup@cryptroot.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/sleep 5";
    };
  };

  system.activationScripts."enroll-secure-boot-keys" = {
    # Ensure signing is done at the end of the activation process,
    # when the bootloader is build, it would be nice to depend on
    # the bootloader, but there is no activation script for that,
    # so this is bit workaround
    deps = [ ];
    text = ''
      if [ -f "/var/lib/sbctl" ]; then
        echo "Secure boot keys already exist"
        exit 0
      fi

      # Create secure boot keys and enroll to uefi
      ${pkgs.sbctl}/bin/sbctl create-keys
      ${pkgs.sbctl}/bin/sbctl enroll-keys
      echo "Secure boot keys has been generated and enrolled"
    '';
  };

  # Sign bootloader with each bootloader build
  # and enroll TPM key during the installation
  boot.loader.systemd-boot.extraInstallCommands = ''
    ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
    ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
    ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/nixos/*.efi
    echo "Bootloader has been signed"

    # Exit early if password file doesn't exist, it means TPM key is probably enrolled already
    if [ ! -f "${diskPasswordFile}" ]; then
      echo "Password file "${diskPasswordFile}" not found, skipping TPM enrollment"
      exit 0
    fi

    # Temporarly enroll TPM key sealed with PCR0 only for the first boot
    ${pkgs.systemd}/bin/systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0 "${luksDevice}" --unlock-key-file="${diskPasswordFile}"
    echo "TPM key enrolled to ${luksDevice}"
  '';

  # Final TPM key enrollment
  systemd.services."enroll-tpm-key" = {
    description = "Enroll TPM key for disk encryption";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      if [ ! -f "${diskPasswordFile}" ]; then
        echo "Password file "${diskPasswordFile}" not found, skipping TPM enrollment"
        exit 1
      fi

      # Enroll TPM key sealed with PCR0 and PCR7 (secure boot)
      ${pkgs.systemd}/bin/systemd-cryptenroll --wipe-slot=tpm2 "${luksDevice}"
      ${pkgs.systemd}/bin/systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,7 "${luksDevice}" --unlock-key-file="${diskPasswordFile}"
      echo "TPM key enrolled to ${luksDevice}"

      # Clean up temporary file securely
      ${pkgs.coreutils}/bin/shred -u "${diskPasswordFile}"
    '';
  };
}

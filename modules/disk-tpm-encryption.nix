{
  config,
  pkgs,
  ...
}: let
  luksDevice = "/dev/disk/by-partlabel/disk-main-luks";
  diskPasswordFile = "/var/lib/disk-password";
in {
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
                mountOptions = ["umask=0077"];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                extraOpenArgs = [];
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
            size = config.hosts.self.swapSize;
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
    wantedBy = ["cryptsetup.target"];
    before = ["systemd-cryptsetup@cryptroot.service"];
    # Prevent boot order cycle
    after = ["systemd-modules-load.service"];
    # wantedBy = [ "systemd-cryptsetup@cryptroot.service" ];
    # before = [ "systemd-cryptsetup@cryptroot.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/sleep 5";
    };
  };

  system.activationScripts."enroll-secure-boot-keys" = {
    deps = [];
    text = ''
      if ${pkgs.sbctl}/bin/sbctl status | grep -qE "Secure Boot:.*Enabled"; then
        echo "Secure boot is already enrolled, skipping creating keys"
        exit 0
      fi

      # Create secure boot keys and enroll to uefi
      ${pkgs.sbctl}/bin/sbctl create-keys

      if ${pkgs.sbctl}/bin/sbctl enroll-keys; then
        echo "Secure boot keys has been enrolled succesfully"
      else
        echo "Failed to enroll Secure boot keys has beend already enrolled"
        ${pkgs.sbctl}/bin/sbctl status
      fi
    '';
  };

  # Sign bootloader with each bootloader build
  # and enroll TPM key during the installation
  boot.loader.systemd-boot.extraInstallCommands = ''
    ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
    ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
    ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/nixos/*bzImage.efi
    echo "Bootloader has been signed"

    # This is a workaround to get provisional key enrolle during installation,
    # enrolmennt through the activation script doesn't work, because the LUKS
    # partition is not ready at that time

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
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ConditionPathExists = "!/run/initramfs";
    };

    script = ''
      set -euo pipefail

      # One time password file is generated during installation for TPM enrollment
      if [ ! -f "${diskPasswordFile}" ]; then
        echo "Password file ${diskPasswordFile} not found, skipping TPM enrollment"
        exit 0
      fi

      echo "Starting TPM key enrollment"
      ${pkgs.sbctl}/bin/sbctl status

      # It is expected that secure boot keys are enrolled already.
      if ! ${pkgs.sbctl}/bin/sbctl status | grep -qE "Setup Mode:.*Disabled"; then
        echo "ERROR: Secure boot is still in Setup Mode"
        exit 1
      fi
      echo "Secure boot in User Mode"

      # Secure boot is required for PCR7 protection.
      if ! ${pkgs.sbctl}/bin/sbctl status | grep -qE "Secure Boot:.*Enabled"; then
        echo "ERROR: Secure boot is not enabled"
        exit 1
      fi
      echo "Secure boot is enabled"

      # Check if the TPM password slot is enrolled
      if ! ${pkgs.cryptsetup}/bin/cryptsetup luksDump "${luksDevice}" | grep -qE "Key Slot [0-9]+: luks2"; then
        echo "ERROR: No password slots found in LUKS device"
        exit 1
      fi
      echo "Password slot found on LUKS device"

      if ! ${pkgs.systemd}/bin/systemd-cryptenroll --wipe-slot=tpm2 "${luksDevice}"; then
        echo "WARNING: Failed to wipe TPM slot, may not exist."
      fi

      # Enroll final TPM key sealed with PCR0 and PCR7
      if ! ${pkgs.systemd}/bin/systemd-cryptenroll \
        --tpm2-device=auto \
        --tpm2-pcrs=0,7 \
        "${luksDevice}" \
        --unlock-key-file="${diskPasswordFile}"; then

        echo "ERROR: Failed to enroll TPM key"
        exit 1
      fi
      echo "TPM key key with PCR0+PCR7"

      if ! ${pkgs.coreutils}/bin/shred -u "${diskPasswordFile}"; then
        echo "ERROR: Failed to delete password file"
        exit 1
      fi
      echo "Password file securely deleted"

    '';
  };
}

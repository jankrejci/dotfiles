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
        device = config.homelab.host.device;
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
            size = config.homelab.host.swapSize;
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
        configurationLimit = 10;
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
  boot.initrd.luks.devices."crypted" = {
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
    before = ["systemd-cryptsetup@crypted.service"];
    # Prevent boot order cycle
    after = ["systemd-modules-load.service"];
    # wantedBy = [ "systemd-cryptsetup@crypted.service" ];
    # before = [ "systemd-cryptsetup@crypted.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/sleep 5";
    };
  };

  # Enroll secure boot keys on first boot when system is in Setup Mode.
  # This must run before enroll-tpm-key service.
  systemd.services."enroll-secure-boot-keys" = {
    description = "Enroll secure boot keys to UEFI";
    wantedBy = ["multi-user.target"];
    before = ["enroll-tpm-key.service"];

    path = with pkgs; [
      sbctl
      e2fsprogs
      systemd
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail

      # Skip if already enrolled
      if sbctl status | grep -qE "Setup Mode:.*Disabled"; then
        echo "Setup Mode disabled, secure boot keys already enrolled"
        exit 0
      fi

      echo "Creating secure boot keys..."
      sbctl create-keys

      set_efi_vars() {
        # EFI variables have immutable flag set by default for safety.
        # We need to remove it before we can enroll secure boot keys.
        local chattr_flag
        case "$1" in
          --immutable) chattr_flag="+i" ;;
          --mutable)   chattr_flag="-i" ;;
          *)           echo "Usage: set_efi_vars --immutable|--mutable"; return 1 ;;
        esac
        local efivars="/sys/firmware/efi/efivars"
        for var in "$efivars"/PK-* "$efivars"/KEK-* "$efivars"/db-* "$efivars"/dbx-*; do
          if [ -f "$var" ]; then
            chattr "$chattr_flag" "$var" 2>/dev/null || true
          fi
        done
      }

      echo "Enrolling keys to UEFI..."
      set_efi_vars --mutable
      # The --microsoft flag is a workaround for T14 gen1
      if ! sbctl enroll-keys --microsoft; then
        set_efi_vars --immutable
        echo "ERROR: Failed to enroll secure boot keys"
        sbctl status
        exit 1
      fi
      set_efi_vars --immutable

      echo "Verifying enrollment..."
      if ! sbctl status | grep -qE "Setup Mode:.*Disabled"; then
        echo "ERROR: Key enrollment verification failed"
        sbctl status
        exit 1
      fi
      echo "Secure boot keys enrolled successfully"

      # Reboot to activate secure boot. The firmware should auto-enable it after
      # keys are enrolled, or user needs to enable it manually in UEFI.
      echo "Rebooting to activate secure boot..."
      systemctl reboot
    '';
  };

  # Enroll provisional TPM key during installation.
  # This allows first boot to unlock without password while secure boot keys
  # are not yet enrolled. Only PCR0 is used since PCR7 requires secure boot.
  boot.loader.systemd-boot.extraInstallCommands = ''
    set -euo pipefail

    # Exit early if password file doesn't exist, TPM key is probably enrolled already
    if [ ! -f "${diskPasswordFile}" ]; then
      echo "Password file not found, skipping provisional TPM enrollment"
      exit 0
    fi

    # Check if TPM slot already exists
    if ${pkgs.systemd}/bin/systemd-cryptenroll "${luksDevice}" | grep -q tpm2; then
      echo "TPM slot already exists, skipping provisional enrollment"
      exit 0
    fi

    # Temporarily enroll TPM key sealed with PCR0 only for the first boot
    echo "Enrolling provisional TPM key (PCR0 only) for first boot..."
    ${pkgs.systemd}/bin/systemd-cryptenroll \
      --tpm2-device=auto \
      --tpm2-pcrs=0 \
      "${luksDevice}" \
      --unlock-key-file="${diskPasswordFile}"
  '';

  # Sign bootloader files after secure boot keys are enrolled.
  # Restarts on each deploy to sign any new kernel/bootloader files.
  systemd.services."sign-bootloader" = {
    description = "Sign bootloader files for secure boot";
    wantedBy = ["multi-user.target"];
    after = ["enroll-secure-boot-keys.service"];
    before = ["enroll-tpm-key.service"];
    restartTriggers = [config.system.nixos.label];

    path = with pkgs; [
      sbctl
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail

      # Skip if secure boot keys not enrolled yet
      if sbctl status | grep -qE "Setup Mode:.*Enabled"; then
        echo "Setup Mode enabled, skipping bootloader signing"
        exit 0
      fi

      echo "Signing bootloader files..."
      sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
      sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI

      # Sign all kernel images
      for kernel in /boot/EFI/nixos/*bzImage.efi; do
        if [ -f "$kernel" ]; then
          sbctl sign -s "$kernel"
        fi
      done

      # Verify signatures
      echo "Verifying signatures..."
      if sbctl verify 2>&1 | grep -q "✗"; then
        echo "ERROR: Unsigned bootloader images found"
        sbctl verify
        exit 1
      fi
      echo "All bootloader files signed successfully"
    '';
  };

  # Final TPM key enrollment
  systemd.services."enroll-tpm-key" = {
    description = "Enroll TPM key for disk encryption";
    wantedBy = ["multi-user.target"];

    path = with pkgs; [
      sbctl
      systemd
      coreutils
    ];

    unitConfig = {
      ConditionPathExists = "!/run/initramfs";
    };

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail

      # One time password file is generated during installation for TPM enrollment
      if [ ! -f "${diskPasswordFile}" ]; then
        echo "Password file ${diskPasswordFile} not found, skipping TPM enrollment"
        exit 0
      fi

      echo "Starting TPM key enrollment"
      sbctl status

      # It is expected that secure boot keys are enrolled already.
      if ! sbctl status | grep -qE "Setup Mode:.*Disabled"; then
        echo "ERROR: Secure boot is still in Setup Mode"
        exit 1
      fi
      echo "Secure boot in User Mode"

      # Secure boot is required for PCR7 protection.
      if ! sbctl status | grep -qE "Secure Boot:.*Enabled"; then
        echo "ERROR: Secure boot is not enabled"
        exit 1
      fi
      echo "Secure boot is enabled"

      # Check if the TPM password slot is enrolled
      if ! systemd-cryptenroll "${luksDevice}" | grep -q "password"; then
        echo "ERROR: No password slots found in LUKS device"
        exit 1
      fi
      echo "Password slot found on LUKS device"

      if ! systemd-cryptenroll --wipe-slot=tpm2 "${luksDevice}"; then
        echo "WARNING: Failed to wipe TPM slot, may not exist."
      fi

      # Enroll final TPM key sealed with PCR0 and PCR7
      if ! systemd-cryptenroll \
        --tpm2-device=auto \
        --tpm2-pcrs=0,7 \
        "${luksDevice}" \
        --unlock-key-file="${diskPasswordFile}"; then

        echo "ERROR: Failed to enroll TPM key"
        exit 1
      fi
      echo "TPM key enrolled with PCR0+PCR7"

      if ! shred -u "${diskPasswordFile}"; then
        echo "ERROR: Failed to delete password file"
        exit 1
      fi
      echo "Password file securely deleted"
    '';
  };

  systemd.services."verify-security-setup" = {
    description = "Verify secure boot and disk encryption setup";
    wantedBy = ["multi-user.target"];
    after = ["enroll-tpm-key.service"];

    path = with pkgs; [
      sbctl
      cryptsetup
      systemd
      jq
      util-linux
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail

      echo "=== Security Setup Verification ==="
      ERRORS=0

      # Check secure boot keys are enrolled
      echo -n "Checking secure boot keys enrollment... "
      if sbctl status | grep -qE "Setup Mode:.*Disabled"; then
        echo "OK"
      else
        echo "FAILED: Secure boot is still in Setup Mode"
        ((ERRORS++))
      fi

      # Check secure boot is enabled
      echo -n "Checking secure boot is enabled... "
      if sbctl status | grep -qE "Secure Boot:.*Enabled"; then
        echo "OK"
      else
        echo "FAILED: Secure boot is not enabled"
        ((ERRORS++))
      fi

      # Check all bootloader images are signed
      echo -n "Checking bootloader images are signed... "
      UNSIGNED=$(sbctl verify | grep -E "✗" || true)
      if [ -z "$UNSIGNED" ]; then
        echo "OK"
      else
        echo "FAILED: Unsigned images found:"
        ((ERRORS++))
      fi

      # Check disk encryption is active
      echo -n "Checking disk encryption is active... "
      if cryptsetup status crypted > /dev/null 2>&1; then
        echo "OK"
      else
        echo "FAILED: Encrypted device 'crypted' not found"
        ((ERRORS++))
      fi

      # Check TPM slot is enrolled
      echo -n "Checking TPM slot is enrolled... "
      if cryptsetup luksDump "${luksDevice}" | grep -qE "systemd-tpm2"; then
        echo "OK"
      else
        echo "FAILED: No TPM slot found"
        ((ERRORS++))
      fi

      # Check TPM is using PCR7 (secure boot)
      echo -n "Checking TPM uses PCR7 (secure boot)... "
      TOKEN_ID=$(cryptsetup luksDump "${luksDevice}" | grep -B1 "systemd-tpm2" | grep -oP '^\s*\K[0-9]+' | head -n1)
      TOKEN_DATA=$(cryptsetup token export "${luksDevice}" --token-id "$TOKEN_ID")
      if echo "$TOKEN_DATA" | jq -e '.["tpm2-pcrs"] | contains([7])' > /dev/null 2>&1; then
        echo "OK"
      else
        echo "FAILED: TPM not sealed with PCR7"
        ((ERRORS++))
      fi

      # Check password slot exists for recovery
      echo -n "Checking password recovery slot exists... "
      if systemd-cryptenroll "${luksDevice}" | grep -q "password"; then
        echo "OK"
      else
        echo "FAILED: No password slots found"
        ((ERRORS++))
      fi

      echo "==================================="
      if [ $ERRORS -gt 0 ]; then
        echo "FAILED: $ERRORS security checks failed"
        exit 1
      else
        echo "SUCCESS: All security checks passed"
      fi
    '';
  };
}

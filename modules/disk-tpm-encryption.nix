# Disk encryption with TPM2 and Secure Boot
#
# - disko: 500MB ESP boot, LUKS-encrypted LVM
# - auto-enrolls secure boot keys on first boot
# - TPM key sealed with PCR0+PCR7
# - password slot kept for recovery
{
  config,
  pkgs,
  ...
}: let
  host = config.homelab.host;
  metricsDir = config.homelab.metricsDir;
  luksDevice = "/dev/disk/by-partlabel/disk-main-luks";
  diskPasswordFile = "/var/lib/disk-password";

  # Sign the systemd-boot binaries and every kernel image on the ESP.
  # Shared by the bootloader install step and the boot-time safety-net service
  # so both paths sign identically. No-ops while still in Setup Mode.
  signBootloader = pkgs.writeShellScript "sign-bootloader" ''
    set -euo pipefail
    export PATH="${pkgs.lib.makeBinPath [pkgs.sbctl]}:$PATH"

    # Skip if secure boot keys not enrolled yet. Capture the output instead of
    # piping into grep -q, which exits on first match and SIGPIPEs sbctl under
    # pipefail, flipping the check exactly when the pattern matches.
    status_output=$(sbctl status)
    if grep -qE "Setup Mode:.*Enabled" <<< "$status_output"; then
      echo "Setup Mode enabled, skipping bootloader signing"
      exit 0
    fi

    # Prune stale entries from sbctl signing database.
    # Bootloader generation cleanup removes old kernels from /boot but
    # sbctl still tracks them, causing verify to fail with "does not exist".
    verify_output=$(sbctl verify 2>&1 || true)
    echo "$verify_output" | while IFS= read -r line; do
      case "$line" in
        *"does not exist")
          file=''${line#*‼ }
          file=''${file% does not exist}
          echo "Removing stale entry: $file"
          sbctl remove-file "$file" || true
          ;;
      esac
    done

    echo "Signing bootloader files..."
    sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
    sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI

    # Sign all kernel images
    for kernel in /boot/EFI/nixos/*bzImage.efi; do
      if [ -f "$kernel" ]; then
        sbctl sign -s "$kernel"
      fi
    done

    # Verify signatures. Capture the output instead of piping into grep -q,
    # which under pipefail can SIGPIPE sbctl and skip the error branch.
    echo "Verifying signatures..."
    verify_output=$(sbctl verify 2>&1 || true)
    if grep -q "✗" <<< "$verify_output"; then
      echo "ERROR: Unsigned bootloader images found"
      echo "$verify_output"
      exit 1
    fi
    echo "All bootloader files signed successfully"
  '';
in {
  # Boot partition and encrypted root partition
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = host.device;
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
            size = host.swapSize;
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

  # The sealed policy below is bound to the PCR values present at enrollment
  # time, so a dbx, secure boot key, or firmware update invalidates it and the
  # host silently drops back to passphrase boot. Re-seal with
  # `nix run .#reenroll-tpm <hostname>`, which needs the passphrase slot kept
  # here as the recovery path.
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

      # Skip if already enrolled. Capture the output instead of piping into
      # grep -q, which exits on first match and SIGPIPEs sbctl under pipefail,
      # flipping the check exactly when the pattern matches.
      status_output=$(sbctl status)
      if grep -qE "Setup Mode:.*Disabled" <<< "$status_output"; then
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
      status_output=$(sbctl status)
      if ! grep -qE "Setup Mode:.*Disabled" <<< "$status_output"; then
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

    # Sign the freshly installed kernel and bootloader here, synchronously in
    # the bootloader install step. The systemd-boot builder copies the new
    # kernel and initrd to the ESP and updates the default boot entry to
    # completion before extraInstallCommands runs, so if signing itself fails,
    # that just-written default entry is already on the ESP unsigned and the
    # switch aborts here. Once signing succeeds, a later activation stage
    # failing can no longer leave a bootable but unsigned entry behind.
    ${signBootloader}

    # Exit early if password file doesn't exist, TPM key is probably enrolled already
    if [ ! -f "${diskPasswordFile}" ]; then
      echo "Password file not found, skipping provisional TPM enrollment"
      exit 0
    fi

    # Check if TPM slot already exists. Capture the output to avoid the
    # grep -q SIGPIPE hazard under pipefail.
    enroll_output=$(${pkgs.systemd}/bin/systemd-cryptenroll "${luksDevice}")
    if grep -q tpm2 <<< "$enroll_output"; then
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

  # Boot-time safety net that signs the ESP after key enrollment. On a normal
  # switch the bootloader install step already signs synchronously via the same
  # script; this covers the first boot right after enrollment, where no install
  # step runs. Restarts on each generation to catch any newly copied files.
  systemd.services."sign-bootloader" = {
    description = "Sign bootloader files for secure boot";
    wantedBy = ["multi-user.target"];
    after = ["enroll-secure-boot-keys.service"];
    before = ["enroll-tpm-key.service"];
    restartTriggers = [config.system.nixos.label];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = signBootloader;
    };
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

      # Capture the output instead of piping into grep -q, which exits on
      # first match and SIGPIPEs sbctl under pipefail, flipping the check
      # exactly when the pattern matches.
      status_output=$(sbctl status)
      echo "$status_output"

      # It is expected that secure boot keys are enrolled already.
      if ! grep -qE "Setup Mode:.*Disabled" <<< "$status_output"; then
        echo "ERROR: Secure boot is still in Setup Mode"
        exit 1
      fi
      echo "Secure boot in User Mode"

      # Secure boot is required for PCR7 protection.
      if ! grep -qE "Secure Boot:.*Enabled" <<< "$status_output"; then
        echo "ERROR: Secure boot is not enabled"
        exit 1
      fi
      echo "Secure boot is enabled"

      # Check if the TPM password slot is enrolled
      enroll_output=$(systemd-cryptenroll "${luksDevice}")
      if ! grep -q "password" <<< "$enroll_output"; then
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
    # Direct dependency on sign-bootloader is needed because the indirect chain
    # through enroll-tpm-key breaks during deploy. enroll-tpm-key has
    # RemainAfterExit=true and no restartTriggers, so systemd considers it
    # already satisfied and starts verify before sign-bootloader finishes.
    #
    # after= alone doesn't enforce ordering when both units restart in the same
    # transaction and sign-bootloader isn't yet queued when verify is queued.
    # requires= forces sign-bootloader into the transaction and refuses to
    # start verify unless the signing completed successfully, so freshly
    # installed kernels are guaranteed to be signed before sbctl checks them.
    after = ["sign-bootloader.service" "enroll-tpm-key.service"];
    requires = ["sign-bootloader.service"];

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

      # Capture the outputs checked below instead of piping into grep -q,
      # which exits on first match and SIGPIPEs the producer under pipefail,
      # flipping the check exactly when the pattern matches.
      status_output=$(sbctl status)

      # Check secure boot keys are enrolled
      echo -n "Checking secure boot keys enrollment... "
      if grep -qE "Setup Mode:.*Disabled" <<< "$status_output"; then
        echo "OK"
      else
        echo "FAILED: Secure boot is still in Setup Mode"
        ERRORS=$((ERRORS + 1))
      fi

      # Check secure boot is enabled
      echo -n "Checking secure boot is enabled... "
      if grep -qE "Secure Boot:.*Enabled" <<< "$status_output"; then
        echo "OK"
      else
        echo "FAILED: Secure boot is not enabled"
        ERRORS=$((ERRORS + 1))
      fi

      # Check all bootloader images are signed
      echo -n "Checking bootloader images are signed... "
      UNSIGNED=$(sbctl verify | grep -E "✗" || true)
      if [ -z "$UNSIGNED" ]; then
        echo "OK"
      else
        echo "FAILED: Unsigned images found:"
        ERRORS=$((ERRORS + 1))
      fi

      # Check disk encryption is active
      echo -n "Checking disk encryption is active... "
      if cryptsetup status crypted > /dev/null 2>&1; then
        echo "OK"
      else
        echo "FAILED: Encrypted device 'crypted' not found"
        ERRORS=$((ERRORS + 1))
      fi

      # Check TPM slot is enrolled
      echo -n "Checking TPM slot is enrolled... "
      luks_dump=$(cryptsetup luksDump "${luksDevice}")
      if grep -qE "systemd-tpm2" <<< "$luks_dump"; then
        echo "OK"
      else
        echo "FAILED: No TPM slot found"
        ERRORS=$((ERRORS + 1))
      fi

      # Check TPM is using PCR7 (secure boot)
      echo -n "Checking TPM uses PCR7 (secure boot)... "
      TOKEN_ID=$(grep -B1 "systemd-tpm2" <<< "$luks_dump" | grep -oP '^\s*\K[0-9]+' | head -n1)
      TOKEN_DATA=$(cryptsetup token export "${luksDevice}" --token-id "$TOKEN_ID")
      if echo "$TOKEN_DATA" | jq -e '.["tpm2-pcrs"] | contains([7])' > /dev/null 2>&1; then
        echo "OK"
      else
        echo "FAILED: TPM not sealed with PCR7"
        ERRORS=$((ERRORS + 1))
      fi

      # Check password slot exists for recovery
      echo -n "Checking password recovery slot exists... "
      enroll_output=$(systemd-cryptenroll "${luksDevice}")
      if grep -q "password" <<< "$enroll_output"; then
        echo "OK"
      else
        echo "FAILED: No password slots found"
        ERRORS=$((ERRORS + 1))
      fi

      # Unsealing happens in the initrd, hours before this unit runs, so the
      # journal is the only record of whether the sealed policy still matched.
      # Everything above still reports OK once the policy goes stale: the slot
      # exists and lists PCR7, it just cannot satisfy the policy any more.
      echo -n "Checking TPM unlocked the disk this boot... "
      POLICY_STALE=0
      # This is systemd-cryptsetup's wording when the sealed PCR policy no
      # longer satisfies the TPM. The exact string is not part of any stable
      # interface, so a systemd change silently makes this read 0. Confirm it
      # against a real stale boot's journal after systemd bumps.
      if journalctl -b --quiet --grep "TPM policy does not match" > /dev/null 2>&1; then
        POLICY_STALE=1
        echo "STALE: boot fell back to the passphrase"
        echo "  re-seal with: nix run .#reenroll-tpm ${host.hostName}"
      else
        echo "OK"
      fi

      # Reported as a metric instead of an error. Every dbx update trips this,
      # and a failing unit here aborts activation, which would make deploys to
      # this host impossible until someone is physically present to re-seal.
      echo "tpm_unlock_policy_stale $POLICY_STALE" > ${metricsDir}/tpm-unlock.prom.tmp
      mv ${metricsDir}/tpm-unlock.prom.tmp ${metricsDir}/tpm-unlock.prom

      echo "==================================="
      if [ $ERRORS -gt 0 ]; then
        echo "FAILED: $ERRORS security checks failed"
        exit 1
      else
        echo "SUCCESS: All security checks passed"
      fi
    '';
  };

  # The catch-all SystemdUnitFailed alert cannot cover a stale policy, because
  # keeping deploys working means verify-security-setup stays green for it.
  homelab.alerts.disk-encryption = [
    {
      alert = "TpmUnlockPolicyStale";
      expr = ''tpm_unlock_policy_stale{host="${host.hostName}"} > 0'';
      for = "15m";
      labels = {
        severity = "warning";
        host = host.hostName;
        type = "host";
      };
      annotations.summary = "TPM unlock policy stale on {{ $labels.host }}, boot needs the passphrase";
    }
  ];
}

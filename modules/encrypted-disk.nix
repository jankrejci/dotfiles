{ config, lib, pkgs, ... }:
let
  luksDevice = "/dev/disk/by-partlabel/disk-main-luks";
  diskPasswordFile = "/tmp/disk-password";
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
  # `systemd-cryptenroll --wipe-slot=tpm2 ${luksPartition}`
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

  # Sign all secure boot relevant images on rebuild,
  # prerequisity is to have secure boot keys generated and pushed into uefi
  # Generate keys `sbctl create-keys`
  # It is needed to have secure boot in setup mode for pushing keys
  # Push keys to uefi `sbctl enroll-keys`
  system.activationScripts."sign-secure-boot" = {
    deps = [ ];
    text = ''
      ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
      ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
      ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/nixos/*.efi
    '';
  };

  system.activationScripts."enroll-tpm" = {
    deps = [ ];
    text = ''
      # Exit early if password file doesn't exist, it means the TPM is probably rolled already
      if [ ! -f "${diskPasswordFile}" ]; then
        echo "Password file not found, skipping TPM enrollment"
        exit 0
      fi
    
      # Enroll TPM using password file
      ${pkgs.systemd}/bin/systemd-cryptenroll --wipe-slot=tpm2 "${luksDevice}" < "${diskPasswordFile}"
      ${pkgs.systemd}/bin/systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,7 "${luksDevice}" < "${diskPasswordFile}"
    
      # Clean up securely
      ${pkgs.coreutils}/bin/shred -u "${diskPasswordFile}"
    '';
  };
}

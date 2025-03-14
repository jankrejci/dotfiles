{ config, lib, pkgs, ... }:
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
        # Systemd boot instead of GRUB is needed for secure boot 
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

  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-partlabel/disk-main-luks";
    preLVM = true;
    allowDiscards = true;
  };

  # Enable TMP support
  security.tpm2.enable = true;
  boot.initrd.systemd = {
    enable = true;
    tpm2.enable = true;
  };

  # Workaround to add delay to avoid TPM unloc timing issues  
  boot.initrd.systemd.services."tpm-delay" = {
    description = "Delay before TPM decryption";
    wantedBy = [ "systemd-cryptsetup@cryptroot.service" ];
    before = [ "systemd-cryptsetup@cryptroot.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/sleep 5";
    };
  };

  # Sign all secure boot relevant images
  system.activationScripts."sign-secure-boot" = {
    text = ''
      ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
      ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
      ${pkgs.sbctl}/bin/sbctl sign -s /boot/EFI/nixos/*.efi
    '';
  };
}

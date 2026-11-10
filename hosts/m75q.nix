# Lenovo M75q server hardware overrides
#
# - AMD microcode and KVM module
# - NVMe data disk with the bulk service data at /mnt/data
{...}: let
  # The installer stages the disk password here for both disks.
  # modules/disk-tpm-encryption.nix seals both to the TPM with it before
  # shredding it, so the data disk unlocks without a prompt too.
  diskPasswordFile = "/var/lib/disk-password";

  # These options are for the data disk. The root disk gets its own
  # through btrfsSubvolume in modules/disk-root-filesystem.nix.
  mountOptions = ["compress=zstd" "noatime"];
in {
  hardware.cpu.amd.updateMicrocode = true;
  boot.kernelModules = ["kvm-amd"];

  # The disk is named "data" with a "luks" partition so disko labels it
  # disk-data-luks and maps it to data. It holds more than immich, so it no
  # longer takes the immich-data names that thinkcenter keeps until its reinstall.
  disko.devices.disk.data = {
    type = "disk";
    # Confirm with lsblk on the installer before running nixos-install.
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions.luks = {
        size = "100%";
        content = {
          type = "luks";
          name = "data";
          passwordFile = diskPasswordFile;
          settings.allowDiscards = true;
          content = {
            type = "btrfs";
            extraArgs = ["-f"];
            # Flat subvolumes so the service data in @immich and @jellyfin can
            # be snapshotted and sent to the twin without the borg repositories.
            subvolumes = {
              "@immich" = {
                mountpoint = "/mnt/data/immich";
                inherit mountOptions;
              };
              "@jellyfin" = {
                mountpoint = "/mnt/data/jellyfin";
                inherit mountOptions;
              };
              "@borg-repos" = {
                mountpoint = "/mnt/data/borg-repos";
                inherit mountOptions;
              };
            };
          };
        };
      };
    };
  };
}

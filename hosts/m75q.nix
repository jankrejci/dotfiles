# Lenovo M75q server hardware overrides
#
# - AMD microcode and KVM module
# - NVMe data disk mirroring thinkcenter's /mnt/immich-data
{...}: let
  # The installer stages the disk password here for both disks. It is shredded
  # once the root disk is sealed to the TPM, so the data disk must be enrolled
  # before the next reboot or it will ask for a passphrase.
  diskPasswordFile = "/var/lib/disk-password";

  # These options are for the immich data disk. The root disk gets its own
  # through btrfsSubvolume in modules/disk-root-filesystem.nix.
  mountOptions = ["compress=zstd" "noatime"];
in {
  hardware.cpu.amd.updateMicrocode = true;
  boot.kernelModules = ["kvm-amd"];

  # The disk is named "immich" with a "luks" partition so disko labels it
  # disk-immich-luks and maps it to immich-data, the same names that
  # homelab/immich.nix expects on thinkcenter.
  disko.devices.disk.immich = {
    type = "disk";
    # Confirm with lsblk on the installer before running nixos-install.
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions.luks = {
        size = "100%";
        content = {
          type = "luks";
          name = "immich-data";
          passwordFile = diskPasswordFile;
          settings.allowDiscards = true;
          content = {
            type = "btrfs";
            extraArgs = ["-f"];
            # Flat subvolumes so the service data in @immich and @jellyfin can
            # be snapshotted and sent to the twin without the borg repositories.
            subvolumes = {
              "@immich" = {
                mountpoint = "/mnt/immich-data/immich";
                inherit mountOptions;
              };
              "@jellyfin" = {
                mountpoint = "/mnt/immich-data/jellyfin";
                inherit mountOptions;
              };
              "@borg-repos" = {
                mountpoint = "/mnt/immich-data/borg-repos";
                inherit mountOptions;
              };
            };
          };
        };
      };
    };
  };
}

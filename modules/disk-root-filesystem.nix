# Root LV content shared by disk-tpm-encryption.nix and
# disk-password-encryption.nix. Both lay out the same ESP + LUKS + LVM disko
# skeleton and only differ in how the root logical volume is formatted, so
# that one piece is factored out and selected by homelab.host.filesystem.
{config}: let
  mountOptions = ["compress=zstd" "noatime"];

  # Subvolumes are flat siblings at the top level. A btrfs snapshot skips any
  # subvolume nested inside it, so a flat layout keeps it obvious what each
  # snapshot contains and lets every subvolume be snapshotted and sent on its
  # own.
  btrfsSubvolume = mountpoint: {
    inherit mountpoint mountOptions;
  };
in
  if config.homelab.host.filesystem == "btrfs"
  then {
    type = "btrfs";
    extraArgs = ["-f"];
    subvolumes = {
      "@root" = btrfsSubvolume "/";
      "@nix" = btrfsSubvolume "/nix";
      "@home" = btrfsSubvolume "/home";
      # /var/lib is its own subvolume because it is the unit replicated to a
      # standby twin: one btrfs send snapshot is atomic across postgres and
      # all other service state that lives under it.
      "@var-lib" = btrfsSubvolume "/var/lib";
      "@snapshots" = btrfsSubvolume "/.snapshots";
    };
  }
  else {
    type = "filesystem";
    format = "ext4";
    mountpoint = "/";
    mountOptions = [
      "defaults"
    ];
  }

# Periodic read-only btrfs snapshots for rolling back a deleted or damaged file
#
# Applies to every host whose root layout has the @snapshots subvolume, see
# disk-root-filesystem.nix. The snapshots live on the same disk, so they are
# not a backup. See the Snapshots section of docs/server-failover.md.
{
  config,
  lib,
  ...
}: {
  config = lib.mkIf (config.fileSystems ? "/.snapshots") {
    services.btrbk.instances.btrbk = {
      onCalendar = "hourly";
      settings = {
        # The default format has only the date, so a second snapshot within
        # the same day would collide with the first.
        timestamp_format = "long";
        # The default keeps every snapshot forever, so retention would never
        # delete anything.
        snapshot_preserve_min = "latest";
        snapshot_preserve = "48h 14d 8w 12m";
        # btrbk resolves the subvolumes through their own mounts, so the
        # top-level subvolume does not need to be mounted.
        volume."/" = {
          snapshot_dir = ".snapshots";
          subvolume = {
            home = {};
            # The default name is the last path component, which would be lib.
            "var/lib".snapshot_name = "var-lib";
          };
        };
      };
    };
  };
}

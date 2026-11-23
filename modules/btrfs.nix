# btrfs maintenance for every host with a btrfs filesystem
#
# - hourly read-only snapshots on hosts with the @snapshots subvolume
# - monthly scrub that verifies every block against its checksum
# - alert on device errors, which a scrub or a normal read records
#
# The snapshots live on the same disk, so they are not a backup. See the
# Snapshots section of docs/server-failover.md.
{
  config,
  lib,
  ...
}: let
  hasBtrfs = lib.any (fs: fs.fsType == "btrfs") (lib.attrValues config.fileSystems);
  hostName = config.homelab.host.hostName;
in {
  config = lib.mkMerge [
    # Only the root layout of disk-root-filesystem.nix has the @snapshots
    # subvolume. The Raspberry Pi roots have no subvolumes to snapshot.
    (lib.mkIf (config.fileSystems ? "/.snapshots") {
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
    })

    (lib.mkIf hasBtrfs {
      # The module picks one mount per device by itself, so the subvolumes of
      # one filesystem are scrubbed once. With a single disk a scrub repairs
      # only the duplicated metadata, but it finds corrupted data before a
      # snapshot holding the only good copy expires.
      services.btrfs.autoScrub.enable = true;

      # The counters are stored on the device and never decrease, so the alert
      # stays until they are reset with btrfs device stats -z after the cause
      # is dealt with. Oneshot keeps it from repeating meanwhile.
      homelab.alerts.btrfs = [
        {
          alert = "BtrfsDeviceErrors";
          expr = ''node_btrfs_device_errors_total{host="${hostName}"} > 0'';
          labels = {
            severity = "critical";
            host = hostName;
            type = "host";
            oneshot = "true";
          };
          annotations.summary = "btrfs recorded {{ $labels.type }} errors on {{ $labels.device }} of {{ $labels.host }}";
        }
      ];
    })
  ];
}

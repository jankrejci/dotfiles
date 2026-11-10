# ThinkCentre server hardware overrides
#
# - Intel microcode updates
# - process collector for detailed monitoring
{...}: {
  hardware.cpu.intel.updateMicrocode = true;

  # Add processes collector for detailed monitoring
  services.prometheus.exporters.node.enabledCollectors = ["processes"];

  # The ext4 data disk at /mnt/immich-data still carries the whole service
  # state. It stays as it is until the reinstall moves this host to the data
  # disk layout of m75q.
  homelab.dataDisk.legacyLayout = true;
}

# ThinkCentre server hardware overrides
#
# - Intel microcode updates
# - process collector for detailed monitoring
{lib, ...}: {
  hardware.cpu.intel.updateMicrocode = true;

  # Add processes collector for detailed monitoring
  services.prometheus.exporters.node.enabledCollectors = ["processes"];
}

# ThinkCentre server hardware overrides
#
# - Intel microcode updates
# - process collector for detailed monitoring
{...}: {
  hardware.cpu.intel.updateMicrocode = true;

  # Point to self-hosted Netbird instance instead of cloud
  homelab.netbird-homelab.managementUrl = "https://api.krejci.io";

  # Add processes collector for detailed monitoring
  services.prometheus.exporters.node.enabledCollectors = ["processes"];
}

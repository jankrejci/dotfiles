{lib, ...}: {
  hardware.cpu.intel.updateMicrocode = true;

  # Add processes collector for detailed monitoring
  services.prometheus.exporters.node.enabledCollectors = ["processes"];
}

# ThinkCentre server hardware overrides
#
# - Intel microcode updates
# - process collector for detailed monitoring
# - watchdog alerts for vpsfree's secondary prometheus
{...}: {
  hardware.cpu.intel.updateMicrocode = true;

  # Add processes collector for detailed monitoring
  services.prometheus.exporters.node.enabledCollectors = ["processes"];

  # Alerts for vpsfree's secondary prometheus to detect thinkcenter failures.
  # Both prometheus instances collect these rules, but only vpsfree's email
  # alerts matter because thinkcenter's ntfy alerts are dead when it is down.
  homelab.alerts.watchdog = [
    {
      alert = "ThinkcenterDown";
      expr = ''up{job="node",host="thinkcenter"} == 0'';
      for = "5m";
      labels = {
        severity = "critical";
        host = "thinkcenter";
        type = "host";
      };
      annotations.summary = "thinkcenter host is unreachable";
    }
    {
      alert = "ThinkcenterPrometheusDown";
      expr = ''up{job="prometheus",host="thinkcenter"} == 0'';
      for = "5m";
      labels = {
        severity = "critical";
        host = "thinkcenter";
        type = "service";
      };
      annotations.summary = "thinkcenter prometheus is down";
    }
    {
      alert = "ThinkcenterNtfyDown";
      expr = ''up{job="ntfy",host="thinkcenter"} == 0'';
      for = "5m";
      labels = {
        severity = "critical";
        host = "thinkcenter";
        type = "service";
      };
      annotations.summary = "thinkcenter ntfy is down";
    }
  ];
}

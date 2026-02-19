# Raspberry Pi 4 hardware overrides
#
# - imports nixos-raspberrypi base module
# - disables EEE on bcmgenet to fix link drops
# - prometheus alert for host monitoring
{
  config,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
  ];

  # Disable EEE on bcmgenet ethernet to prevent link drops. RPi4 ethernet PHY
  # has unstable EEE implementation that causes frequent carrier loss events.
  # See: https://github.com/raspberrypi/linux/issues/4289
  #
  # Cannot use systemd.link [EnergyEfficientEthernet] section because it runs
  # during udev probe, before the driver initializes the PHY. The ethtool
  # interface returns ENODEV at that point. This is a known systemd limitation:
  # https://github.com/systemd/systemd/issues/16445
  environment.systemPackages = [pkgs.ethtool];
  systemd.services.disable-eee = {
    description = "Disable Energy Efficient Ethernet on bcmgenet";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ethtool}/bin/ethtool --set-eee end0 eee off";
    };
  };

  # Point to self-hosted Netbird instance for migration testing
  homelab.netbird-homelab.managementUrl = "https://api.krejci.io";

  homelab.alerts.hosts = [
    {
      alert = "Rpi4Down";
      expr = ''up{instance=~"rpi4.*", job="node"} == 0'';
      labels = {
        severity = "critical";
        host = config.homelab.host.hostName;
        type = "host";
      };
      annotations.summary = "rpi4 host is down";
    }
  ];
}

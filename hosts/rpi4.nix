{
  config,
  inputs,
  ...
}: {
  imports = [
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
  ];

  homelab.alerts.hosts = [
    {
      alert = "rpi4-down";
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

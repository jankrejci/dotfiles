# Raspberry Pi 3 with RAK2245 LoRaWAN concentrator HAT
{
  config,
  inputs,
  lib,
  ...
}: {
  imports = [inputs.nixos-raspberrypi.nixosModules.raspberry-pi-3.base];

  # Enable SPI for RAK2245 communication with SX1301 concentrator
  hardware.raspberry-pi.extra-config = lib.mkAfter ''
    dtparam=spi=on
  '';

  # Prometheus alert for host monitoring
  homelab.alerts.hosts = [
    {
      alert = "Rak2245Down";
      expr = ''up{instance=~"rak2245.*", job="node"} == 0'';
      labels = {
        severity = "critical";
        host = config.homelab.host.hostName;
        type = "host";
        oneshot = "true";
      };
      annotations.summary = "rak2245 LoRaWAN gateway is down";
    }
  ];
}

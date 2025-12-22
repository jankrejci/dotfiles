# Raspberry Pi 3 with RAK2245 LoRaWAN concentrator HAT
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [inputs.nixos-raspberrypi.nixosModules.raspberry-pi-3.base];

  # Software UART for when hardware TX pin is dead
  environment.systemPackages = [
    (pkgs.callPackage ../pkgs/soft-uart-tx.nix {})
  ];

  # Enable SPI for RAK2245 communication with SX1301 concentrator
  # Enable uart0 overlay to properly configure GPIO14/15 for UART TX/RX.
  # Without this, GPIO14 stays in GPIO mode instead of ALT0 UART function.
  hardware.raspberry-pi.extra-config = lib.mkAfter ''
    dtparam=spi=on
    dtoverlay=uart0
  '';

  # Prometheus alert for host monitoring
  homelab.alerts.hosts = [
    {
      alert = "Rak2245Down";
      expr = ''up{host="rak2245", job="node"} == 0'';
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

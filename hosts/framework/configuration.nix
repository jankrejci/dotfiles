{ ... }:
let
  ethDevice = "enp195s0f4u1";
  wlanDevice = "wlp1s0";
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Workaround to avoid the VPNs default route with metric 50
  # steals all the connection, there is configuration for both
  # systemd-networkd and for  network manager
  systemd.network.networks = {
    "10-${ethDevice}" = {
      matchConfig.Name = ethDevice;
      DHCP = "yes";
      dhcpV4Config.RouteMetric = 48;
    };
    "10-${wlanDevice}" = {
      matchConfig.Name = wlanDevice;
      DHCP = "yes";
      dhcpV4Config.RouteMetric = 49;
    };
  };
  networking.networkmanager.ensureProfiles = {
    profiles = {
      "${ethDevice}" = {
        connection = {
          id = ethDevice;
          interface-name = ethDevice;
          type = "ethernet";
        };
        ipv4 = {
          method = "auto";
          route-metric = 48;
        };
      };
      "${wlanDevice}" = {
        connection = {
          id = wlanDevice;
          interface-name = wlanDevice;
          type = "wifi";
        };
        ipv4 = {
          method = "auto";
          route-metric = 49;
        };
      };
    };
  };
}

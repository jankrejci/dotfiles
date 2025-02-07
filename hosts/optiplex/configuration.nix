{ ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-4146767d-b4f4-4a2e-be33-f12e11165724".device = "/dev/disk/by-uuid/4146767d-b4f4-4a2e-be33-f12e11165724";

  # Workaround to avoid the VPNs default route with metric 50
  # steals all the connection, there is configuration for both
  # systemd-networkd and for  network manager
  systemd.network.networks = {
    "10-enp0s25" = {
      matchConfig.Name = "enp0s25";
      DHCP = "yes";
      dhcpV4Config.RouteMetric = 48;
    };
    "10-enp0s29u1u2u1i5" = {
      matchConfig.Name = "enp0s29u1u2u1i5 ";
      DHCP = "yes";
      dhcpV4Config.RouteMetric = 49;
    };
  };
  networking.networkmanager.ensureProfiles = {
    profiles = {
      enp0s25 = {
        connection = {
          id = "enp0s25";
          interface-name = "enp0s25";
          type = "ethernet";
        };
        ipv4 = {
          method = "auto";
          route-metric = 48;
        };
      };
      enp0s29u1u2u1i5 = {
        connection = {
          id = "enp0s29u1u2u1i5";
          interface-name = "enp0s29u1u2u1i5";
          type = "ethernet";
        };
        ipv4 = {
          method = "auto";
          route-metric = 49;
        };
      };
    };
  };

}

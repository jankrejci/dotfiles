{ ... }:
let
  ethDevice = "enp0s25";
  dockDevice = "enp0s29u1u2u1i5";
in
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
    "10-${ethDevice}" = {
      matchConfig.Name = ethDevice;
      DHCP = "yes";
      dhcpV4Config.RouteMetric = 48;
    };
    "10-${dockDevice}" = {
      matchConfig.Name = dockDevice;
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
      "${dockDevice}" = {
        connection = {
          id = dockDevice;
          interface-name = dockDevice;
          type = "ethernet";
        };
        ipv4 = {
          method = "auto";
          route-metric = 49;
        };
      };
    };
  };
  nix.extraOptions = ''
    secret-key-files = /home/jkr/.config/nix/signing-key
  '';
}

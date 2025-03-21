# disk.nix - Disk configuration for all hosts
{ config, lib, ... }:

{
  # Disko configuration
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = config.hosts.self.device;
        content = {
          type = "gpt";
          partitions = {
            boot = {
              start = "1M";
              end = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            swap = {
              start = "512M";
              size = config.hosts.self.swapSize;
              content = {
                type = "swap";
                randomEncryption = false;
              };
            };
            root = {
              start = "end+1M";
              end = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };

  # This is needed for initial activation of disko
  boot.initrd.systemd.enable = lib.mkDefault true;
}

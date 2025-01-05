{ ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../../modules/common.nix
      ../../modules/ssh.nix
      ../../modules/wg-client.nix
    ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;

  networking.hostName = "rpi4";
  networking.networkmanager.enable = true;

  services.openssh = {
    listenAddresses = [
      { addr = "192.168.99.2"; port = 22; }
    ];
  };

  users.users.jkr = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcPS15FwxQjt4xZJk0+VzKqLTh/rikF0ZI4GFyOTLoD jkr@optiplex-rpi4"
    ];
  };

  networking.wireguard.interfaces.wg0 = {
    ips = [ "192.168.99.2/24" ];
    privateKeyFile = "/home/jkr/.wg/jkr-rpi4";
  };

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "24.11"; # Did you read the comment?

}


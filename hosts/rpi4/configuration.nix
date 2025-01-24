{ config, ... }:
{
  imports = [
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

  services.openssh = {
    listenAddresses = [
      { addr = "192.168.99.2"; port = 22; }
    ];
  };

  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcPS15FwxQjt4xZJk0+VzKqLTh/rikF0ZI4GFyOTLoD jkr@optiplex-rpi4"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwuE1yPiKiX7SL1mSDZB6os9COPdOqrWfh9rUNBpfOq jkr@thinkpad-rpi4"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqz14JAcEgnxuy4xIkUiots+K1bo1uQGd/Tn7mRWyu+ jkr@latitude-rpi4"
    ];
  };

  sops = {
    defaultSopsFile = ./secrets.yaml;
    validateSopsFiles = true;

    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };

    secrets = {
      wg-private-key = { };
    };
  };

  networking.wg-quick.interfaces.wg0 = {
    address = [ "192.168.99.2/24" ];
    privateKeyFile = config.sops.secrets.wg-private-key.path;
    dns = [ "192.168.99.1" ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;
    listenAddress = "192.168.99.2";
  };

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "24.11"; # Did you read the comment?

}


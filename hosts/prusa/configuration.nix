{ hostConfig, ... }:
{
  security.sudo.wheelNeedsPassword = false;

  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcPS15FwxQjt4xZJk0+VzKqLTh/rikF0ZI4GFyOTLoD jkr@optiplex-rpi4"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwuE1yPiKiX7SL1mSDZB6os9COPdOqrWfh9rUNBpfOq jkr@thinkpad-rpi4"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqz14JAcEgnxuy4xIkUiots+K1bo1uQGd/Tn7mRWyu+ jkr@latitude-rpi4"
    ];
  };

  nix.settings.trusted-public-keys = [
    "jkr-prusa:mfZZpEV+n0c0Pe4dTJyLSnNz6oQO2Kx86S3RcG9mwXk="
  ];

  # TODO add obico plugin and enable the port
  services.octoprint = {
    enable = true;
    host = hostConfig.ipAddress;
  };
}


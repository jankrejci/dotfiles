{ pkgs, ... }:

{
  # Server-side SSH configuration
  services.openssh = {
    enable = true;

    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };

    # Consider changing this if you need SSH access from other machines
    listenAddresses = [
      { addr = "0.0.0.0"; port = 22; } # IPv4: all interfaces
    ];
  };

  users.users.jkr = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcPS15FwxQjt4xZJk0+VzKqLTh/rikF0ZI4GFyOTLoD jkr@optiplex"
    ];
  };
}

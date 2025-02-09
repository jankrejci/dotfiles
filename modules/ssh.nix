{ lib, hostConfig, ... }:
{
  # Server-side SSH configuration
  services.openssh = {
    enable = true;

    listenAddresses = [
      { addr = hostConfig.ipAddress; port = 22; }
    ];

    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = lib.mkForce "no";
    };
  };

  systemd.services.sshd.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };
}

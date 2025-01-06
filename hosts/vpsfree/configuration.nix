{ ... }:
{
  imports = [
    ./vpsadminos.nix
    ../../modules/common.nix
    ../../modules/ssh.nix
    ../../modules/wg-server.nix
  ];

  networking.hostName = "vpsfree";

  services.openssh = {
    listenAddresses = [
      { addr = "192.168.99.1"; port = 22; }
    ];
  };

  users.users.jkr = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN85SndW/OerKK8u2wTxmHcTn4hEtUJmctj9wnseBYtS jkr@optiplex-vpsfree"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICWjLMaGa0MgRX0K1i2+me5iWe3Kpw/9RrpWMZLDtOWr jkr@thinkpad-vpsfree"
    ];
  };

  systemd.extraConfig = ''
    DefaultTimeoutStartSec=900s
  '';

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "24.11";
}

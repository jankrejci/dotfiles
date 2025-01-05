{ config, pkgs, ... }:
{
  imports = [
    ./vpsadminos.nix
    ../../modules/ssh.nix
  ];

  users.users.jkr = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN85SndW/OerKK8u2wTxmHcTn4hEtUJmctj9wnseBYtS jkr@optiplex"
    ];
  };

  networking.hostName = "vpsfree";

  systemd.extraConfig = ''
    DefaultTimeoutStartSec=900s
  '';

  time.timeZone = "Europe/Amsterdam";

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "24.11";
}

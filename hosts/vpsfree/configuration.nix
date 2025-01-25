{ ... }:
{
  imports = [
    ./vpsadminos.nix
    ../../modules/grafana.nix
  ];

  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN85SndW/OerKK8u2wTxmHcTn4hEtUJmctj9wnseBYtS jkr@optiplex-vpsfree"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICWjLMaGa0MgRX0K1i2+me5iWe3Kpw/9RrpWMZLDtOWr jkr@thinkpad-vpsfree"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/XIewPQt4B37PnUVItz8+LZ/SGWjf8JogSEZEGC5Cm jkr@latitude-vpsfree"
    ];
  };

  systemd.extraConfig = ''
    DefaultTimeoutStartSec=900s
  '';

  security.sudo.wheelNeedsPassword = false;
}

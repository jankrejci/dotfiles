{ ... }:
{
  # TODO use the ssh-authorized-keys.pub file
  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN85SndW/OerKK8u2wTxmHcTn4hEtUJmctj9wnseBYtS jkr@optiplex-vpsfree"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICWjLMaGa0MgRX0K1i2+me5iWe3Kpw/9RrpWMZLDtOWr jkr@thinkpad-vpsfree"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/XIewPQt4B37PnUVItz8+LZ/SGWjf8JogSEZEGC5Cm jkr@latitude-vpsfree"
    ];
  };

  nix.settings.trusted-public-keys = [
    "jkr@optiplex:KwH9qv7qCHd+npxC0FUFCApM1rP6GSbB8Ze983CCT8o="
  ];

  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  systemd.extraConfig = ''
    DefaultTimeoutStartSec=900s
  '';

  # Avoid collision between networking and vpsadminos module
  systemd.network.networks."98-all-ethernet".DHCP = "no";

  security.sudo.wheelNeedsPassword = false;
}

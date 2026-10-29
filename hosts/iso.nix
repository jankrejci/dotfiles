# NixOS installer ISO configuration
#
# - root SSH login allowed for nixos-anywhere
# - UCSI module disabled for Framework compatibility
#
# The Netbird setup key comes from modules/load-keys.nix, which the SD card
# images share. A second definition here made NixOS join both into one file,
# so the installer enrolled with the key written twice and was rejected.
{
  lib,
  pkgs,
  ...
}: {
  # Allow nixos-anywhere to login as root for installation
  services.openssh.settings.PermitRootLogin = lib.mkForce "yes";

  # Avoid UCSI complains on framework laptop
  boot.kernelParams = ["ucsi.ignore_altmode=1" "ucsi.debug=1" "typec.blacklist=1"];

  systemd.services.disable-ucsi = {
    description = "Disable UCSI kernel module";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.kmod}/bin/rmmod ucsi_acpi";
      RemainAfterExit = true;
    };
  };
}

# NixOS installer ISO configuration
#
# - embeds Netbird setup key for VPN during install
# - root SSH login allowed for nixos-anywhere
# - UCSI module disabled for Framework compatibility
{
  lib,
  pkgs,
  ...
}: let
  # Environment variable set by build-installer script
  netbirdSetupKey = builtins.getEnv "NETBIRD_SETUP_KEY";
  setupKeySource = "/etc/netbird/setup-key";
  setupKeyFolder = "/var/lib/netbird-homelab";
  setupKeyPath = "${setupKeyFolder}/setup-key";
in {
  # Embed the setup key in the ISO. The ISO uses read-only squashfs,
  # so we place it in /etc and copy to /var/lib on boot.
  environment.etc."netbird/setup-key" = {
    text = builtins.trace "Loading Netbird setup key for ISO installer" netbirdSetupKey;
    mode = "0600";
    user = "root";
    group = "root";
  };

  # Ensure the persistent target directory exists
  systemd.tmpfiles.rules = [
    "d ${setupKeyFolder} 0755 root root -"
  ];

  # Copy the setup key from squashfs /etc to tmpfs /var/lib on boot.
  # Netbird expects the key in /var/lib which is on tmpfs in the live ISO.
  systemd.services.netbird-key-copy = {
    description = "Copy Netbird Setup Key";
    wantedBy = ["multi-user.target"];
    before = ["netbird-homelab.service"];
    after = ["local-fs.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      if [ -f "${setupKeySource}" ]; then
        echo "Copying Netbird setup key from ${setupKeySource} to ${setupKeyPath}"
        cp "${setupKeySource}" "${setupKeyPath}"
        chmod 600 "${setupKeyPath}"
        chown root:root "${setupKeyPath}"
      else
        echo "No ${setupKeySource} found, skipping copy."
      fi
    '';
  };

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

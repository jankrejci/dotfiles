# Inject Netbird setup key into images during build.
# NETBIRD_SETUP_KEY env var is set by build-sdcard/build-installer scripts.
{...}: let
  netbirdSetupKey = builtins.getEnv "NETBIRD_SETUP_KEY";
  setupKeySource = "/etc/netbird/setup-key";
  setupKeyFolder = "/var/lib/netbird-homelab";
  setupKeyPath = "${setupKeyFolder}/setup-key";
in {
  # Embed the setup key in /etc (works for both ISO and SD card)
  environment.etc."netbird/setup-key" = {
    text = builtins.trace "Loading Netbird setup key for image" netbirdSetupKey;
    mode = "0600";
  };

  # Ensure the persistent target directory exists
  systemd.tmpfiles.rules = [
    "d ${setupKeyFolder} 0755 root root -"
  ];

  # Copy the setup key to persistent storage during boot.
  # Needed because /etc may be read-only on some image types.
  systemd.services.netbird-key-copy = {
    description = "Copy Netbird Setup Key";
    wantedBy = ["multi-user.target"];
    before = ["netbird-homelab.service" "netbird-homelab-enroll.service"];
    after = ["local-fs.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      if [ -f "${setupKeySource}" ]; then
        echo "Copying Netbird setup key to ${setupKeyPath}"
        cp "${setupKeySource}" "${setupKeyPath}"
        chmod 600 "${setupKeyPath}"
      fi
    '';
  };
}

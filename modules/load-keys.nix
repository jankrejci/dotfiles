{...}: let
  # Environment variable needs to be set by the install script
  netbirdSetupKey = builtins.getEnv "NETBIRD_SETUP_KEY";
  setupKeySource = "/etc/netbird/setup-key";
  setupKeyFolder = "/var/lib/netbird-homelab";
  setupKeyPath = "${setupKeyFolder}/setup-key";
in {
  # Embed the setup key in the ISO
  environment.etc."netbird/setup-key" = {
    text = builtins.trace "Loading Netbird setup key for installer" netbirdSetupKey;
    mode = "0600";
    user = "root";
    group = "root";
  };

  # Ensure the persistent target directory exists
  systemd.tmpfiles.rules = [
    "d ${setupKeyFolder} 0755 root root -"
  ];

  # Copy the setup key to the persistent storage during first boot
  # This is needed because /etc is read-only on the ISO
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
}

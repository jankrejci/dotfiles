{...}: let
  # Enviroment variable needs to be set by the install script
  wgPrivateKey = builtins.getEnv "WG_PRIVATE_KEY";
  wgKeySource = "/etc/wireguard/wg-key";
  wgKeyFolder = "/var/lib/wireguard";
  wgKeyPath = "${wgKeyFolder}/wg-key";
  keyUser = "systemd-network";
  keyGroup = "systemd-network";
in {
  environment.etc."wireguard/wg-key" = {
    text = builtins.trace "Loading host config ${wgPrivateKey}" wgPrivateKey;
    mode = "0600";
    user = keyUser;
    group = keyGroup;
  };

  # Ensure the persistent target directory exists
  systemd.tmpfiles.rules = [
    "d ${wgKeyFolder} 0700 ${keyUser} ${keyGroup} -"
  ];

  # TODO find a better way to avoid copying the key
  # Copy the key to the persistent storage during the first boot
  systemd.services.wireguard-key-copy = {
    description = "Copy Wireguard Key";
    wantedBy = ["multi-user.target"];
    before = ["network.target"];
    after = ["local-fs.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      if [ -f "${wgKeySource}" ]; then
        echo "Copying wireguard key from ${wgKeySource} to ${wgKeyPath}"
        cp "${wgKeySource}" "${wgKeyPath}"
        chmod 600 "${wgKeyPath}"
        chown ${keyUser}:${keyGroup} "${wgKeyPath}"
      else
        echo "No ${wgKeySource} found, skipping copy."
      fi
    '';
  };
}

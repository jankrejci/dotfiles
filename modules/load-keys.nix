{ ... }:
let
  # Enviroment variable needs to be set by the install script
  wgPrivateKey = builtins.getEnv "WG_PRIVATE_KEY";
  wgKeySource = "/etc/wireguard/wg-key";
  wgKeyFolder = "/var/lib/wireguard";
  wgKeyPath = "${wgKeyFolder}/wg-key";
  keyUser = "root";
  keyGroup = "root";
in
{
  environment.etc."wireguard/wg-key" = {
    text = wgPrivateKey;
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
  system.activationScripts."copy-wg-key" = {
    text = ''
      set -x
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



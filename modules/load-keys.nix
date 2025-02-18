{ pkgs, hostConfig, ... }:
let
  # Import the admin key file to decrypt shared secrets.yaml
  homeDir = builtins.getEnv "HOME";
  adminKeyFilePath = builtins.toFile "admin-keys.txt" (builtins.readFile "${homeDir}/.config/sops/age/keys.txt");

  # Decrypt host's private age key
  decryptedSecret = pkgs.runCommand "decrypted-secret" { buildInputs = [ pkgs.sops ]; } ''
    export SOPS_AGE_KEY_FILE="${adminKeyFilePath}"
    mkdir -p $out
    sops --decrypt --extract '["sops_private_key"]' ${../hosts/${hostConfig.hostName}/secrets.yaml} > $out/keys.txt
    # echo "DEBUG: Copied key to $out/keys.txt" >&2
    # echo "DEBUG: Contents of keys.txt: " >&2
    # cat $out/keys.txt >&2
  '';

  ageKeySource = "/etc/sops/age/keys.txt";
  ageKeyFolder = "/var/lib/sops/age";
  ageKeyPath = "${ageKeyFolder}/keys.txt";
  user = "root";
  group = "root";
in
{
  # Inject the key into /etc, this is removed with the first nixos-rebuild
  environment.etc."sops/age/keys.txt" = {
    source = "${decryptedSecret}/keys.txt";
    mode = "0600";
    user = user;
    group = group;
  };

  # Ensure the persistent target directory exists
  systemd.tmpfiles.rules = [
    "d ${ageKeyFolder} 0700 ${user} ${group} -"
  ];

  # Copy the key to the persistent storage during the first boot
  system.activationScripts.copyAgeKey = {
    text = ''
      set -x
      if [ -f "${ageKeySource}" ]; then
        echo "Copying age key from ${ageKeySource} to ${ageKeyPath}"
        cp "${ageKeySource}" "${ageKeyPath}"
        chmod 600 "${ageKeyPath}"
        chown ${user}:${group} "${ageKeyPath}"
      else
        echo "No ${ageKeySource} found, skipping copy."
      fi
    '';
  };
}

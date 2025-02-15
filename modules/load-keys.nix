{ pkgs, hostConfig, ... }:
let
  # Import the key file
  homeDir = builtins.getEnv "HOME";
  adminKeyFilePath = builtins.toFile "admin-keys.txt" (builtins.readFile "${homeDir}/.config/sops/age/keys.txt");

  # Decrypt the secrets using the correct path
  decryptedSecret = pkgs.runCommand "decrypted-secret" { buildInputs = [ pkgs.sops ]; } ''
    export SOPS_AGE_KEY_FILE="${adminKeyFilePath}"
    mkdir -p $out
    sops --decrypt --extract '["sops_private_key"]' ${../hosts/${hostConfig.hostName}/secrets.yaml} > $out/keys.txt
    echo "DEBUG: Copied key to $out/keys.txt" >&2
    echo "DEBUG: Contents of keys.txt: " >&2
    cat $out/keys.txt >&2
  '';

  ageKeySource = "/etc/sops/age/keys.txt";
  ageKeyFolder = "/var/lib/sops/age";
  ageKeyPath = "${ageKeyFolder}/keys.txt";
  user = "root";
  group = "root";
in
{
  environment.etc."sops/age/keys.txt" = {
    source = "${decryptedSecret}/keys.txt";
    mode = "0600";
    user = user;
    group = group;
  };

  # Ensure the target directory exists
  systemd.tmpfiles.rules = [
    # "d ${ageKeyFolder} ${user} ${group} -"
    "d /var/lib/sops/age 0700 root root -"
  ];

  # Activation script to copy the key if it exists
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

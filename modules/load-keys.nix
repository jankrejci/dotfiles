{ pkgs, lib, hostConfig, ... }:
# TODO generate, inject and forget those keys during the instalation
let
  # Import the admin key file to decrypt shared secrets.yaml
  homeDir = builtins.getEnv "HOME";
  adminKeyFilePath = builtins.toFile "admin-keys.txt" (builtins.readFile "${homeDir}/.config/sops/age/keys.txt");

  # Decrypt host's private age key
  decryptedSecret = pkgs.runCommand "decrypted-secret" { buildInputs = [ pkgs.sops ]; } ''
    export SOPS_AGE_KEY_FILE="${adminKeyFilePath}"
    mkdir -p $out
    sops --decrypt --extract '["sops_private_key"]' ${../hosts/${hostConfig.hostName}/secrets.yaml} > $out/keys.txt
  '';

  ageKeySource = "/etc/sops/age/keys.txt";
  ageKeyFolder = "/var/lib/sops/age";
  ageKeyPath = "${ageKeyFolder}/keys.txt";
  keysUser = "root";
  keysGroup = "root";
in
{
  # Inject the key into /etc, this is removed after the first rebuild
  environment.etc."sops/age/keys.txt" = {
    source = "${decryptedSecret}/keys.txt";
    mode = "0600";
    user = keysUser;
    group = keysGroup;
  };

  # Use the /etc path for keys until the first rebuild
  sops.age.keyFile = lib.mkForce "/etc/sops/age/keys.txt";

  # Ensure the persistent target directory exists
  systemd.tmpfiles.rules = [
    "d ${ageKeyFolder} 0700 ${keysUser} ${keysGroup} -"
  ];

  # TODO find a better way to avoid copying the key
  # Copy the key to the persistent storage during the first boot
  system.activationScripts.copyAgeKey = {
    text = ''
      set -x
      if [ -f "${ageKeySource}" ]; then
        echo "Copying age key from ${ageKeySource} to ${ageKeyPath}"
        cp "${ageKeySource}" "${ageKeyPath}"
        chmod 600 "${ageKeyPath}"
        chown ${keysUser}:${keysGroup} "${ageKeyPath}"
      else
        echo "No ${ageKeySource} found, skipping copy."
      fi
    '';
  };
}

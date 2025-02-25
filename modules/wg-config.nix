# Generate wireguard configuration for the non-NixOS hosts
{ pkgs, hostConfig, hostInfo, ... }:
let
  hostName = hostConfig.hostName;
  domain = "vpn";

  adminKeyFilePath = "${builtins.getEnv "HOME"}/.config/sops/age/keys.txt";

  # Copy admin key to the derivation
  ageKeyFile = pkgs.runCommand "age-key.txt" { } ''
    mkdir -p $out
    echo '${builtins.readFile adminKeyFilePath}' > $out/keys.txt
  '';

  # Decrypt the wg private key inside the derivation
  decryptedKey = pkgs.runCommand "decrypted-wg-key" { buildInputs = [ pkgs.sops ]; } ''
    export SOPS_AGE_KEY_FILE=${ageKeyFile}/keys.txt
    mkdir -p $out
    # TODO we can possibly return the key immediatelly without the need for intermidiate storage
    sops --decrypt --extract '["wg_private_key"]' "${../hosts/${hostName}/secrets.yaml}" > $out/wg_private_key
  '';

  wgConfig = ''
    [Interface]
    PrivateKey = ${builtins.readFile "${decryptedKey}/wg_private_key"}
    Address = ${hostConfig.ipAddress}
    DNS = 192.168.99.1, ${domain}

    [Peer]
    PublicKey = ${hostInfo.vpsfree.wgPublicKey}
    AllowedIPs = 192.168.99.0/24
    Endpoint = 37.205.13.227:51820
  '';
in
{
  config = {
    system.build.wgConfig = pkgs.runCommand "wg-${hostName}" { } ''
      out_folder="$out/${hostName}"
      # Create the result/hostName folder for the configuration output
      mkdir -p $out_folder
      # Write the final configuration
      echo "${wgConfig}" > $out_folder/wg0.conf
      # Generate QR code for easy android configuration
      echo '${wgConfig}' | ${pkgs.qrencode}/bin/qrencode -o $out_folder/wg0.png
    '';
  };
}

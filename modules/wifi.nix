{ config, pkgs, ... }:
# TODO merge with raspberry config
let
  # Define paths to the decrypted secrets
  ssidPath = config.sops.secrets."wifi_ssid".path;
  pskPath = config.sops.secrets."wifi_psk".path;

  # Path where the wpa_supplicant configuration will be generated
  wpaConfigFolder = "/var/lib/wpa_supplicant";
  wpaConfigPath = "${wpaConfigFolder}/wpa_supplicant.conf";
in
{
  # TODO find out how to share multiple wifi config in a better way
  sops = {
    secrets = {
      "wifi_ssid" = { mode = "0400"; owner = "systemd-network"; };
      "wifi_psk" = { mode = "0400"; owner = "systemd-network"; };
    };
  };

  # Ensure wpa_supplicant is installed
  environment.systemPackages = [ pkgs.wpa_supplicant ];
  environment.etc."wpa_supplicant.conf".source = wpaConfigPath;

  # Systemd service to generate the wpa_supplicant configuration at runtime
  systemd.services."wpa-generate-config" = {
    description = "Generate wpa_supplicant configuration from SOPS secrets";
    after = [ "network-pre.target" ];
    before = [ "wpa_supplicant.service" ];
    wantedBy = [ "multi-user.target" ];
    script = ''
      SSID=$(cat ${ssidPath})
      PSK=$(cat ${pskPath})
      mkdir -p ${wpaConfigFolder}
      cat > ${wpaConfigPath} <<EOF
      network={
        ssid="$SSID"
        psk="$PSK"
      }
      EOF
      chmod 600 ${wpaConfigPath}
      chown root:root ${wpaConfigPath}
    '';
  };

  # Configure wpa_supplicant to use the generated configuration
  networking.wireless = {
    enable = true;
    userControlled.enable = false;
    interfaces = [ "wlan0" ]; # Replace with your actual wireless interface
  };

  # Ensure wpa_supplicant starts after the configuration is generated
  systemd.services.wpa_supplicant.after = [ "generate-wifi-config.service" ];
}

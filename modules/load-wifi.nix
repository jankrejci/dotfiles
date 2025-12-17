# Inject WiFi credentials into SD card images during build.
# WIFI_SSID and WIFI_PASSWORD env vars are set by build-sdcard script.
# iwd expects files in /var/lib/iwd/, so we use populateRootCommands.
{lib, ...}: let
  wifiSsid = builtins.getEnv "WIFI_SSID";
  wifiPassword = builtins.getEnv "WIFI_PASSWORD";
  hasWifi = wifiSsid != "" && wifiPassword != "";
in {
  sdImage.populateRootCommands = lib.mkIf hasWifi (
    builtins.trace "Injecting WiFi credentials for ${wifiSsid}" ''
      mkdir -p ./files/var/lib/iwd
      cat > "./files/var/lib/iwd/${wifiSsid}.psk" << 'EOF'
      [Security]
      Passphrase=${wifiPassword}

      [Settings]
      AutoConnect=true
      EOF
      chmod 600 "./files/var/lib/iwd/${wifiSsid}.psk"
    ''
  );
}

# Inject keys directly into SD card images during build.
# Environment variables are set by build-sdcard script.
{lib, ...}: let
  netbirdSetupKey = builtins.getEnv "NETBIRD_SETUP_KEY";
  setupKeyPath = "/var/lib/netbird-homelab/setup-key";

  wifiSsid = builtins.getEnv "WIFI_SSID";
  wifiPassword = builtins.getEnv "WIFI_PASSWORD";
  hasWifi = wifiSsid != "" && wifiPassword != "";
in {
  sdImage.populateRootCommands =
    builtins.trace "Injecting keys into SD image" ''
      mkdir -p ./files/var/lib/netbird-homelab
      echo -n '${netbirdSetupKey}' > "./files${setupKeyPath}"
      chmod 600 "./files${setupKeyPath}"
    ''
    + lib.optionalString hasWifi (
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

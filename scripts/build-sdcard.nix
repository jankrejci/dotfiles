# Builds NixOS sdcard image that can be used for aarch64
# Raspberry Pi machines.
# Usage: nix run .#build-sdcard <hostname> [--wifi <ssid>]
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "build-sdcard";
  runtimeInputs = with pkgs; [
    age
    coreutils
    curl
    jq
    nix
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    function configure_wifi() {
      # Not in interactive terminal, skip WiFi
      [ -t 0 ] || {
        info "Not interactive, skipping WiFi configuration"
        return
      }

      read -r -p "Configure WiFi? [y/N] " response
      case "$response" in
        y|Y) ;;
        *) info "Skipping WiFi configuration"; return ;;
      esac

      WIFI_SSID=$(ask_for_token "WiFi SSID")
      export WIFI_SSID

      WIFI_PASSWORD=$(ask_for_token "WiFi password")
      export WIFI_PASSWORD

      info "WiFi credentials set for $WIFI_SSID"
    }

    function main() {
      local hostname=""
      local wifi_ssid=""

      while [ $# -gt 0 ]; do
        case "$1" in
          --wifi) wifi_ssid="$2"; shift ;;
          *) hostname="$1" ;;
        esac
        shift
      done

      hostname=$(require_and_validate_hostname "$hostname")
      local -r image_name="$hostname-sdcard"

      NETBIRD_SETUP_KEY=$(generate_netbird_key "$hostname")
      export NETBIRD_SETUP_KEY

      if [ -n "$wifi_ssid" ]; then
        load_wifi_credentials "$wifi_ssid"
      else
        configure_wifi
      fi

      info "Building image for host: $hostname"

      # Use -L to print full build logs instead of progress bar
      nix build ".#image.sdcard.$hostname" \
        --impure \
        -o "$image_name"

      info "Image built successfully: $image_name"

      unset NETBIRD_SETUP_KEY WIFI_SSID WIFI_PASSWORD
      info "Secrets cleared, build complete"
    }

    main "$@"
  '';
}

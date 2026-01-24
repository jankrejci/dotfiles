# Builds NixOS sdcard image that can be used for aarch64
# Raspberry Pi machines.
# `nix run .#build-sdcard hostname`
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "build-sdcard";
  runtimeInputs = with pkgs; [
    coreutils
    curl
    jq
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    function configure_wifi() {
      get_wifi_from_sops && {
        info "Using WiFi credentials from secrets.yaml for $WIFI_SSID"
        return
      }

      # Not in interactive terminal, skip WiFi
      [ -t 0 ] || {
        info "No WiFi in secrets.yaml and not interactive, skipping"
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
      local -r hostname=$(require_and_validate_hostname "$@")
      local -r image_name="$hostname-sdcard"

      NETBIRD_SETUP_KEY=$(generate_netbird_key "$hostname")
      export NETBIRD_SETUP_KEY

      configure_wifi

      info "Building image for host: $hostname"

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

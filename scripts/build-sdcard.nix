# Builds NixOS sdcard image that can be used for aarch64
# Raspberry Pi machines.
# Usage: nix run .#build-sdcard <hostname>
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
    util-linux
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    function main() {
      local -r hostname=$(require_and_validate_hostname "$@")
      local -r image_name="$hostname-sdcard"

      NETBIRD_SETUP_KEY=$(generate_netbird_key "$hostname")
      export NETBIRD_SETUP_KEY

      load_wifi_networks

      info "Building image for host: $hostname"

      # Use -L to print full build logs instead of progress bar
      nix build ".#image.sdcard.$hostname" \
        --impure \
        -o "$image_name"

      info "Image built successfully: $image_name"

      unset NETBIRD_SETUP_KEY WIFI_NETWORKS
      info "Secrets cleared, build complete"

      print_flash_instructions "$(realpath "$image_name"/sd-image/*.img)" "SD card"
    }

    main "$@"
  '';
}

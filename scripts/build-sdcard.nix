# Builds NixOS sdcard image that can be used for aarch64
# Raspberry Pi machines.
# Usage: nix run .#build-sdcard <hostname> [--allow-kernel-build]
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

      # Checked before the setup key exists, since generating one already
      # registers it with Netbird management.
      [ "''${2:-}" = "$ALLOW_KERNEL_BUILD" ] || require_cached_kernel "$hostname"

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

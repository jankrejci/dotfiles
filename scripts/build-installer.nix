# Builds iso image for USB stick that can be used to boot
# and install the NixOS system on x86-64 machine.
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "build-installer";
  runtimeInputs = with pkgs; [
    coreutils
    curl
    jq
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    function main() {
      local -r hostname="iso"

      NETBIRD_SETUP_KEY=$(generate_netbird_key "$hostname" --reusable)
      export NETBIRD_SETUP_KEY

      # Build the image using nixos-generators via flake output
      # Pass the setup key via environment variable to Nix
      nix build ".#image.installer" \
        --impure \
        -o "iso-image"

      info "ISO image built successfully: iso-image"

      unset NETBIRD_SETUP_KEY
      info "Setup key securely deleted, build complete"
    }

    main "$@"
  '';
}

# Builds iso image for USB stick that can be used to boot
# and install the NixOS system on x86-64 machine.
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "build-installer";
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

    function main() {
      local -r hostname="iso"
      local -r master_key="$HOME/.age/master.txt"
      local -r iso_key_encrypted="secrets/iso-host-key.age"

      NETBIRD_SETUP_KEY=$(generate_netbird_key "$hostname" --reusable)
      export NETBIRD_SETUP_KEY

      # Decrypt ISO host key for agenix secret decryption
      ISO_HOST_KEY=$(age -d -i "$master_key" "$iso_key_encrypted")
      export ISO_HOST_KEY

      # Build the image using nixos-generators via flake output
      # Pass secrets via environment variables to Nix
      # Use -L to print full build logs instead of progress bar
      nix build ".#image.installer" \
        --impure \
        -o "iso-image"

      info "ISO image built successfully: iso-image"

      unset NETBIRD_SETUP_KEY ISO_HOST_KEY
      info "Secrets securely deleted, build complete"
    }

    main "$@"
  '';
}

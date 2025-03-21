{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "build-installer";
  runtimeInputs = with pkgs; [
    coreutils
    wireguard-tools
  ];
  text = ''
    #!/usr/bin/env bash
    set -euo pipefail

    readonly HOSTNAME="iso"


    # Create a temporary directory for the build
    echo "Generating WireGuard keys for $HOSTNAME..."
    TMP_DIR=$(mktemp -d)
    wg genkey > "$TMP_DIR/wg-key"
    wg pubkey < $(cat "$TMP_DIR/wg-key") > "hosts/$HOSTNAME/wg-key.pub"

    echo "Public key generated and saved to hosts/$HOSTNAME/wg-key.pub"
    echo "Building ISO image with embedded private key..."

    # Build the image using nixos-generators via flake output
    # Pass the temporary directory path to Nix
    nix build ".#image.installer" \
      --impure \
      --include "$TMP_DIR/wg-key" \
      -o "iso-image"

    echo "ISO image built successfully: iso-image"

    # Clean up private key
    shred -zu "$TMP_DIR//wg-key"
    rm -rf "$TMP_DIR"

    echo "Private key securely deleted, build complete."
  '';
}

{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "build-installer";
  runtimeInputs = with pkgs; [
    coreutils
  ];
  text = ''
    #!/usr/bin/env bash
    set -euo pipefail
  
    readonly HOSTNAME="iso"

    echo "Building installer image "
  
    # Build the image - clean and simple
    nix build ".#image.installer.$HOSTNAME" -o "$HOSTNAME-image"
  
    echo "Image built successfully: $HOSTNAME-image"
  '';
}

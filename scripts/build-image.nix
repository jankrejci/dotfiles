{ pkgs, ... }:

pkgs.writeShellScriptBin "build-image" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  if [ $# -ne 1 ]; then
    echo "Usage: build-image HOSTNAME"
    exit 1
  fi
  
  hostname="$1"
  echo "Building image for host: $hostname"
  
  # Build the image - clean and simple
  nix build ".#image.sdImage.$hostname" -o "$hostname-sdcard.img"
  
  echo "Image built successfully: $hostname-sdcard.img"
''

{ pkgs, ... }:

pkgs.writeShellScriptBin "build-image" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  if [ $# -ne 1 ]; then
    echo "Usage: build-image HOSTNAME"
    exit 1
  fi
  
  # Create temporary root build to be copied to the sdcard image root
  local -r $TEMP="/tmp/build/root"
  mkdir -p "$TEMP"

  declare -r WG_KEY_FOLDER="/var/lib/wireguard"
  declare -r WG_KEY_PATH="$WG_KEY_FOLDER/wg-key"


  mkdir -p "$TEMP/$WG_KEY_FOLDER"
  touch "$TEMP/$WG_KEY_PATH

  hostname="$1"
  echo "Building image for host: $hostname"
  
  # Build the image - clean and simple
  nix build ".#image.sdImage.$hostname" -o "$hostname-sdcard.img"
  
  echo "Image built successfully: $hostname-sdcard.img"
''

{ pkgs, ... }:

pkgs.writeShellScriptBin "build-image" ''
  #!${pkgs.bash}/bin/bash
  set -euo pipefail
  
  if [ $# -ne 1 ]; then
    echo "Usage: build-image HOSTNAME"
    exit 1
  fi
  
  hostname="$1"
  echo "Building image for host: $hostname"
  
  # Build using the existing image output
  nix build ".#image.$hostname" -o "result-$hostname-image"
  
  echo "Image built successfully: result-$hostname-image"
''

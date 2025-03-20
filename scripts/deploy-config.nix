{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "deploy-config";
  runtimeInputs = with pkgs; [
    gnused
    deploy-rs
  ];
  text = ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Display usage information
    if [ $# -lt 1 ]; then
      echo "Usage: deploy HOSTNAME [--skip-checks]"
    fi

    readonly hostname="$1"
     
    # Check if LOCAL_KEY is set
    if [ -z "$LOCAL_KEY" ]; then
      # Try to use the default location if not explicitly set
      if [ -f "$HOME/.config/nix/signing-key.pem" ]; then
        LOCAL_KEY="$HOME/.config/nix/signing-key.pem"
        echo "Using signing key from: $LOCAL_KEY"
      else
        echo "Error: LOCAL_KEY environment variable not set and default key not found"
        echo "Please set LOCAL_KEY to your signing key path or create a key at ~/.config/nix/signing-key.pem"
        exit 1
      fi
    fi

    # Export the LOCAL_KEY for deploy-rs to use
    export LOCAL_KEY

    # Run deploy-rs
    echo "Deploying to $hostname..."
    deploy ".#$hostname" "$@"
  ''
  ;
}

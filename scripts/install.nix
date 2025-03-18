{ nixos-anywhere, pkgs, ... }:

pkgs.writeShellApplication {
  name = "nixos-install";
  runtimeInputs = with pkgs; [
    sops
    coreutils
    util-linux
    gnused
    nixos-anywhere
  ];
  text = ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Usage
    if [ $# -lt 1 ]; then
      echo "Usage: $0 hostname [target]"
      exit 1
    fi

    TARGET="iso.vpn"

    ADMIN_KEY_PATH="$HOME/.config/sops/age/keys.txt"

    AGE_KEY_FOLDER="var/cache/sops/age"
    AGE_KEY_PATH="$AGE_KEY_FOLDER/keys.txt"

    DISK_PASSWORD_PATH="/tmp/disk-password"

    # Usage
    if [ $# -lt 1 ]; then
      echo "Usage: $0 hostname"
      exit 1
    fi
    HOSTNAME="$1"

    # Create a temporary directory
    temp=$(mktemp -d)

    # Function to cleanup temporary directory on exit
    cleanup() {
      rm -rf "$temp"
      # Cleanup temporary password file
      if [ -f "$DISK_PASSWORD_PATH" ]; then
        shred -u "$DISK_PASSWORD_PATH"
      fi
      # Cleanup password variables
      DISK_PASSWORD_CONFIRM=""
      DISK_PASSWORD=""
    }

    trap cleanup EXIT INT TERM

    # Prompt for password with confirmation
    while true; do
      echo -n "Enter disk encryption password: "
      read -rs DISK_PASSWORD
      echo

      echo -n "Confirm password: "
      read -rs DISK_PASSWORD_CONFIRM
      echo

      if [ "$DISK_PASSWORD" = "$DISK_PASSWORD_CONFIRM" ]; then
        break
      else
        echo "Passwords do not match. Please try again."
      fi
    done

    # Create temporary password file
    echo "$DISK_PASSWORD" >"$DISK_PASSWORD_PATH"

    # Create the directory where sops expects to find the age key
    install -d -m755 "$temp/$AGE_KEY_FOLDER"
    
    # Decrypt host's private age key
    export SOPS_AGE_KEY_FILE="$ADMIN_KEY_PATH"
    
    # Decrypt your private key from the secrets and copy it to the temporary directory
    sops --decrypt --extract '["sops_private_key"]' "hosts/$HOSTNAME/secrets.yaml" >"$temp/$AGE_KEY_PATH"
    
    # Set restricted permissions
    chmod 600 "$temp/$AGE_KEY_PATH"

    # Install NixOS to the host system with our secrets
    nixos-anywhere \
      --generate-hardware-config nixos-generate-config "hosts/$HOSTNAME/hardware-configuration.nix" \
      --disk-encryption-keys "$DISK_PASSWORD_PATH" "$DISK_PASSWORD_PATH" \
      --extra-files "$temp" \
      --flake ".#$HOSTNAME" \
      --target-host "root@$TARGET"
  '';
}

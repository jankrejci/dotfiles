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

    # Store the disk password in the /tmp folder
    # and erase it later after the disk encryption
    LOCAL_DISK_PASSWORD_FOLDER="/tmp"
    LOCAL_DISK_PASSWORD_PATH="$LOCAL_DISK_PASSWORD_FOLDER/disk-password"
    # The password must be persistent, it is used to enroll TPM key
    # during the first boot and then it is erased
    REMOTE_DISK_PASSWORD_FOLDER="/var/lib"
    REMOTE_DISK_PASSWORD_PATH="$REMOTE_DISK_PASSWORD_FOLDER/disk-password"

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
      if [ -f "$LOCAL_DISK_PASSWORD_PATH" ]; then
        shred -u "$LOCAL_DISK_PASSWORD_PATH"
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

    # Create temporary password file for disk encryption
    echo -n "$DISK_PASSWORD" >"$LOCAL_DISK_PASSWORD_PATH"
    # Create the directory where TPM expects disk password
    # during the key enrollment
    install -d -m755 "$temp/$REMOTE_DISK_PASSWORD_FOLDER"
    cp "$LOCAL_DISK_PASSWORD_PATH" "$temp/$REMOTE_DISK_PASSWORD_FOLDER"
    chmod 600 "$temp/$REMOTE_DISK_PASSWORD_FOLDER"

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
      --disk-encryption-keys "$REMOTE_DISK_PASSWORD_PATH" "$LOCAL_DISK_PASSWORD_PATH" \
      --extra-files "$temp" \
      --flake ".#$HOSTNAME" \
      --target-host "root@$TARGET"
  '';
}

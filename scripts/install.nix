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

    # Store the disk password in the /tmp folder
    # and erase it later after the disk encryption
    LOCAL_DISK_PASSWORD_FOLDER="/tmp"
    LOCAL_DISK_PASSWORD_PATH="$LOCAL_DISK_PASSWORD_FOLDER/disk-password"
    # The password must be persistent, it is used to enroll TPM key
    # during the first boot and then it is erased
    REMOTE_DISK_PASSWORD_FOLDER="/var/lib"
    REMOTE_DISK_PASSWORD_PATH="$REMOTE_DISK_PASSWORD_FOLDER/disk-password"

    WG_KEY_FOLDER="/var/lib/wireguard"
    WG_PRIVATE_KEY_PATH="$WG_KEY_FOLDER/wg-key"
    WG_PUBLIC_KEY_PATH="$WG_KEY_FOLDER/wg-key.pub"

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

 
    # Generate new wireguard keys
    WG_PRIVATE_KEY=$(${pkgs.wireguard-tools}/bin/wg genkey)
    WG_PUBLIC_KEY=$(echo "$WG_PRIVATE_KEY" | ${pkgs.wireguard-tools}/bin/wg pubkey)
    # Check if host directory exists
    if [ ! -d "hosts/$HOSTNAME" ]; then
      echo "Host directory hosts/$HOSTNAME does not exist"
      exit 1
    fi  
    # Write public key to file
    echo "$WG_PUBLIC_KEY" > "hosts/$HOSTNAME/wg-key.pub"
    echo "Wireguard public key written to hosts/$HOSTNAME/wg-key.pub"
    # Create the directory where wiregusrd expects to find the private key
    install -d -m755 "$temp/$WG_KEY_FOLDER"
    echo "$WG_PRIVATE_KEY" > "$temp/$WG_PRIVATE_KEY_PATH"
    chmod 600 "$temp/$WG_PRIVATE_KEY_PATH"
    echo "$WG_PUBLIC_KEY" > "$temp/$WG_PUBLIC_KEY_PATH"
    chmod 644 "$temp/$WG_PUBLIC_KEY_PATH"

    # Install NixOS to the host system with our secrets
    nixos-anywhere \
      --generate-hardware-config nixos-generate-config "hosts/$HOSTNAME/hardware-configuration.nix" \
      --disk-encryption-keys "$REMOTE_DISK_PASSWORD_PATH" "$LOCAL_DISK_PASSWORD_PATH" \
      --extra-files "$temp" \
      --flake ".#$HOSTNAME" \
      --target-host "root@$TARGET"
  '';
}

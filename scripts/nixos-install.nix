{ nixos-anywhere, pkgs, ... }:

pkgs.writeShellApplication {
  name = "nixos-install";
  runtimeInputs = with pkgs; [
    coreutils
    util-linux
    gnused
    nixos-anywhere
  ];
  text = ''
    #!/usr/bin/env bash
    set -euo pipefail
    trap cleanup EXIT INT TERM

    readonly TARGET="iso.vpn"
    # The password must be persistent, it is used to enroll TPM key
    # during the first boot and then it is erased
    readonly REMOTE_DISK_PASSWORD_FOLDER="/var/lib"
    readonly REMOTE_DISK_PASSWORD_PATH="$REMOTE_DISK_PASSWORD_FOLDER/disk-password"
    # Where wireguard expects the key
    readonly WG_KEY_FOLDER="/var/lib/wireguard"
    readonly WG_KEY_PATH="$WG_KEY_FOLDER/wg-key"

    readonly WG_KEY_USER="systemd-network"
    readonly WG_KEY_GROUP="systemd-network"

    # Create a temporary directory for extra files
    TEMP=$(mktemp -d)
    readonly TEMP

    # Function to cleanup temporary directory on exit
    function cleanup() {
      rm -rf "$TEMP"

      # Cleanup temporary password file
      if [ -f "$LOCAL_DISK_PASSWORD_PATH" ]; then
        shred -u "$LOCAL_DISK_PASSWORD_PATH"
      fi
    }

    # Ask for password with confirmation
    function ask_for_disk_password() {
      local disk_password
      local confirm_password

      while true; do
        read -r -s -p "Enter disk encryption password: " disk_password; echo
        read -r -s -p "Confirm disk encryption password: " confirm_password; echo

        if [ -z "$disk_password" ]; then
          echo "Password cannot be empty. Please try again."
          continue
        fi

        if [ "$disk_password" = "$confirm_password" ]; then
          break
        fi
        echo "Passwords do not match. Please try again."
      done

      echo "$disk_password"
    }

    # Generate random password that can be changed later
    function generate_disk_password() {
      local disk_password

      echo "Generating disk password"
      disk_password=$(head -c 12 /dev/urandom | base64 | tr -d '/+=' | head -c 16)

      echo "$disk_password"
    }

    function set_disk_password() {
      local generate_password
      read -r -p "Auto-generate disk encryption password? [Y/n] " generate_password

      # Create temporary password file to be passed to nixos-anywhere
      local -r tmp_folder=$(mktemp -d)
      readonly LOCAL_DISK_PASSWORD_PATH="$tmp_folder/disk-password"

      local disk_password
      # Default to Yes if empty or starts with Y/y
      if [[ -z "$generate_password" || "$generate_password" =~ ^[Yy] ]]; then
        disk_password=$(generate_disk_password)
        echo "Disk password auto-generated."
      else
        disk_password=$(ask_for_disk_password)
        echo "Disk password has been set."
      fi

      echo -n "$disk_password" >"$LOCAL_DISK_PASSWORD_PATH"
      # Create the directory where TPM expects disk password during
      # the key enrollment, it will be removed after the fisrt boot
      install -d -m755 "$TEMP/$REMOTE_DISK_PASSWORD_FOLDER"
      cp "$LOCAL_DISK_PASSWORD_PATH" "$TEMP/$REMOTE_DISK_PASSWORD_FOLDER"

      echo "Disk password successfully installed."
    }

    function generate_wg_key() {
      local -r hostname="$1"

      # Generate new wireguard keys
      echo "Generating wireguard key"
      local -r wg_private_key=$(${pkgs.wireguard-tools}/bin/wg genkey)
      local -r wg_public_key=$(echo "$wg_private_key" | ${pkgs.wireguard-tools}/bin/wg pubkey)

      # Check if host directory exists
      local host_folder="hosts/$hostname"
      if [ ! -d "$host_folder" ]; then
        echo "Host directory $host_folder does not exist"
        exit 1
      fi
      local -r pubkey_path="$host_folder/wg-key.pub"

      # Write public key to the host file
      echo "$wg_public_key" > "$pubkey_path"
      echo "Wireguard public key written to $pubkey_path"

      # Create the directory where wiregusrd expects to find the private key
      install -d -m700 "$TEMP/$WG_KEY_FOLDER"
      echo "$wg_private_key" > "$TEMP/$WG_KEY_PATH"
      chmod 600 "$TEMP/$WG_KEY_PATH"
    }

    function main() {
      if [ $# -lt 1 ]; then
        echo "Usage: $0 hostname"
        exit 1
      fi

      local -r hostname="$1"

      set_disk_password

      generate_wg_key "$hostname"

      # Install NixOS to the host system with our secrets
      nixos-anywhere \
        --disk-encryption-keys "$REMOTE_DISK_PASSWORD_PATH" "$LOCAL_DISK_PASSWORD_PATH" \
        --extra-files "$TEMP" \
        --chown "$WG_KEY_FOLDER" "$WG_KEY_USER:$WG_KEY_GROUP" \
        --chown "$WG_KEY_PATH" "$WG_KEY_USER:$WG_KEY_GROUP" \
        --flake ".#$hostname" \
        --target-host "root@$TARGET"
    }

    main "$@"
  '';
}

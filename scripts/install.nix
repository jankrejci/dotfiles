{ nixos-anywhere, pkgs, ... }:

pkgs.writeShellApplication {
  name = "install";
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

    TARGET="iso.vpn"
    # The password must be persistent, it is used to enroll TPM key
    # during the first boot and then it is erased
    REMOTE_DISK_PASSWORD_FOLDER="/var/lib"
    REMOTE_DISK_PASSWORD_PATH="$REMOTE_DISK_PASSWORD_FOLDER/disk-password"
    # Where wireguard expects the key
    WG_KEY_FOLDER="/var/lib/wireguard"
    WG_KEY_PATH="$WG_KEY_FOLDER/wg-key"

    # Function to cleanup temporary directory on exit
    function cleanup() {
      rm -rf "$TEMP"

      # Cleanup temporary password file
      if [ -f "$LOCAL_DISK_PASSWORD_PATH" ]; then
        shred -u "$LOCAL_DISK_PASSWORD_PATH"
      fi
    }

    function generate_disk_password() {
      # Create temporary password file to be passed to nixos-anywhere
      local -r tmp_folder=$(mktemp -d)
      readonly LOCAL_DISK_PASSWORD_PATH="$tmp_folder/disk-password"

      # Prompt for password with confirmation
      while true; do
        echo -n "Enter disk encryption password: "
        local disk_password
        read -rs disk_password
        echo

        echo -n "Confirm password: "
        local disk_password_confirm
        read -rs disk_password_confirm
        echo

        if [ "$disk_password" = "$disk_password_confirm" ]; then
          break
        else
          echo "Passwords do not match. Please try again."
        fi
      done

      echo -n "$disk_password" >"$LOCAL_DISK_PASSWORD_PATH"
      # Create the directory where TPM expects disk password during
      # the key enrollment, it will be removed after the fisrt boot
      install -d -m755 "$TEMP/$REMOTE_DISK_PASSWORD_FOLDER"
      cp "$LOCAL_DISK_PASSWORD_PATH" "$TEMP/$REMOTE_DISK_PASSWORD_FOLDER"
    }

     function generate_wg_key() {
      local -r hostname="$1"

      # Generate new wireguard keys
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

      # Create a temporary directory for extra files
      declare -r TEMP=$(mktemp -d)

      generate_disk_password

      generate_wg_key "$hostname"

      # Install NixOS to the host system with our secrets
      nixos-anywhere \
        --generate-hardware-config nixos-generate-config "hosts/$hostname/hardware-configuration.nix" \
        --disk-encryption-keys "$REMOTE_DISK_PASSWORD_PATH" "$LOCAL_DISK_PASSWORD_PATH" \
        --extra-files "$TEMP" \
        --flake ".#$hostname" \
        --target-host "root@$TARGET"
    }

    main "$@"
  '';
}

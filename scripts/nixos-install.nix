# Install nixos remotely. It is expected that the host
# is booted via USB stick and accesible on iso.nb.krejci.io
# `nix run .#nixos-install`
{
  pkgs,
  lib,
  nixos-anywhere,
}:
pkgs.writeShellApplication {
  name = "nixos-install";
  runtimeInputs = with pkgs; [
    coreutils
    util-linux
    gnused
    nixos-anywhere
    iputils
    openssh
    jq
    curl
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    trap cleanup EXIT INT TERM

    readonly TARGET="root@iso.nb.krejci.io"
    # The password must be persistent, it is used to enroll TPM key
    # during the first boot and then it is erased
    readonly REMOTE_DISK_PASSWORD_FOLDER="/var/lib"
    readonly REMOTE_DISK_PASSWORD_PATH="$REMOTE_DISK_PASSWORD_FOLDER/disk-password"

    # Where netbird expects the setup key
    readonly NETBIRD_KEY_FOLDER="/var/lib/netbird-homelab"
    readonly NETBIRD_KEY_PATH="$NETBIRD_KEY_FOLDER/setup-key"

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


    function set_disk_password() {
      local disk_password
      disk_password=$(ask_for_token "disk encryption password")

      # Create temporary password file to be passed to nixos-anywhere
      local -r tmp_folder=$(mktemp -d)
      readonly LOCAL_DISK_PASSWORD_PATH="$tmp_folder/disk-password"
      echo -n "$disk_password" >"$LOCAL_DISK_PASSWORD_PATH"
      # Create the directory where TPM expects disk password during
      # the key enrollment, it will be removed after the fisrt boot
      install -d -m755 "$TEMP/$REMOTE_DISK_PASSWORD_FOLDER"
      cp "$LOCAL_DISK_PASSWORD_PATH" "$TEMP/$REMOTE_DISK_PASSWORD_FOLDER"

      info "Disk password successfully installed"
    }

    function install_netbird_key() {
      local -r hostname="$1"
      local -r setup_key=$(generate_netbird_key "$hostname")

      # Create directory for Netbird setup key
      install -d -m755 "$TEMP/$NETBIRD_KEY_FOLDER"
      echo -n "$setup_key" > "$TEMP/$NETBIRD_KEY_PATH"
      chmod 600 "$TEMP/$NETBIRD_KEY_PATH"

      info "Netbird setup key installed for $hostname"
    }

    function check_secure_boot_setup_mode() {
      info "Checking secure boot setup mode"

      if ssh "$TARGET" \
        'nix-shell -p sbctl --run "sbctl status" | grep -qE "Setup Mode:.*Enabled"' 2>/dev/null; then
        return
      fi

      warn "Target secure boot not in Setup Mode"
      read -r -p "Continue anyway? [y/N] " response

      case "$response" in
        y|Y)
          ;;
        *)
          info "Installation aborted"
          exit 1
          ;;
      esac

    }

    function main() {
      local -r hostname=$(require_and_validate_hostname "$@")

      require_ssh_reachable "$TARGET"
      check_secure_boot_setup_mode

      set_disk_password

      # Desktops use netbird-user with SSO login, no setup key needed
      host_needs_netbird_key "$hostname" && install_netbird_key "$hostname"

      # Install NixOS to the host system with our secrets
      nixos-anywhere \
        --disk-encryption-keys "$REMOTE_DISK_PASSWORD_PATH" "$LOCAL_DISK_PASSWORD_PATH" \
        --extra-files "$TEMP" \
        --flake ".#$hostname" \
        --target-host "$TARGET"
    }

    main "$@"
  '';
}

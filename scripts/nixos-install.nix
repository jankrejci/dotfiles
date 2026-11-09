# Install nixos remotely. It is expected that the host
# is booted via USB stick and accesible on iso.nb.krejci.io
# `nix run .#nixos-install`
#
# Before booting the stick, switch Secure Boot on and reset it to Setup Mode in
# the firmware setup. Setup Mode enforces nothing whatever the switch says, and
# the switch decides whether the firmware enforces the keys the first boot
# enrolls. Everything after the install runs without a hand on the target.
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

    # The UEFI global variable that reads 1 while the firmware is in Setup Mode
    readonly SETUP_MODE_VAR="SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"

    # Create a temporary directory for extra files
    TEMP=$(mktemp -d)
    readonly TEMP

    # Function to cleanup temporary directory on exit
    function cleanup() {
      rm -rf "$TEMP"

      # Cleanup temporary password file. An exit before the password prompt
      # leaves the path unset, which nounset would turn into a second error.
      if [ -f "''${LOCAL_DISK_PASSWORD_PATH:-}" ]; then
        shred -u "$LOCAL_DISK_PASSWORD_PATH"
      fi
    }


    function set_disk_password() {
      local disk_password
      disk_password=$(ask_for_token "disk encryption password")

      # Create temporary password file to be passed to nixos-anywhere
      local -r tmp_folder=$(mktemp -d)
      readonly LOCAL_DISK_PASSWORD_PATH="$tmp_folder/disk-password"
      # The file is created private, because the default umask made it world
      # readable here and, carried over by the extra files, on the target too
      # until the TPM enrollment shreds it.
      (umask 077 && echo -n "$disk_password" >"$LOCAL_DISK_PASSWORD_PATH")
      # Create the directory where TPM expects disk password during
      # the key enrollment, it will be removed after the fisrt boot
      install -d -m755 "$TEMP/$REMOTE_DISK_PASSWORD_FOLDER"
      install -m600 "$LOCAL_DISK_PASSWORD_PATH" "$TEMP/$REMOTE_DISK_PASSWORD_FOLDER/"

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

      # The firmware variable answers directly, where sbctl through nix-shell
      # needed a nixpkgs download on the installer and read any failure of it
      # as a target outside Setup Mode. The fifth byte holds the mode, after
      # four bytes of attributes.
      local setup_mode
      # The variable name is a constant of this script and must expand here,
      # because the remote shell does not know it.
      # shellcheck disable=SC2029
      setup_mode=$(ssh "$TARGET" \
        "od -An -tu1 -j4 -N1 /sys/firmware/efi/efivars/$SETUP_MODE_VAR" 2>/dev/null |
        tr -d ' ') || true
      [ "$setup_mode" = 1 ] && {
        info "Setup Mode is on, Secure Boot must be switched on in the firmware too"
        return
      }

      # The first boot creates fresh keys and only enrolls them in Setup Mode.
      # Keys from an earlier install stay in charge otherwise, and they reject
      # the bootloader signed with the fresh ones.
      warn "Target secure boot not in Setup Mode"
      warn "The installed system will not pass secure boot with keys from an earlier install"
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
      # nixos-anywhere points ssh at a throwaway known_hosts, so every
      # connection announces the installer key again, and it requests a tty
      # with no terminal on stdin. LogLevel=ERROR drops both notices while
      # real connection failures still print.
      nixos-anywhere \
        --ssh-option LogLevel=ERROR \
        --disk-encryption-keys "$REMOTE_DISK_PASSWORD_PATH" "$LOCAL_DISK_PASSWORD_PATH" \
        --extra-files "$TEMP" \
        --flake ".#$hostname" \
        --target-host "$TARGET"

      print_secure_boot_steps
    }

    # The rest of the secure boot setup runs on the target by itself over two
    # boots. The first enrolls the keys, signs the bootloader and reboots, and
    # the second seals the TPM key to PCR0+7 and shreds the password file.
    function print_secure_boot_steps() {
      info "Installation finished, the target now reboots twice by itself to"
      info "enroll the secure boot keys and seal the TPM key"
      info "Check afterwards with: systemctl status verify-security-setup"
    }

    main "$@"
  '';
}

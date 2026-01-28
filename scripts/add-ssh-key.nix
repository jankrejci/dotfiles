# Generate SSH key pair and authorize for target host
#
# - creates ed25519 key with password protection
# - adds public key to ssh-authorized-keys.conf
# - configures ~/.ssh/config entry
# - commits changes to git
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "add-ssh-key";
  runtimeInputs = with pkgs; [
    coreutils
    openssh
    gnused
    gnupg
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    readonly KEYTYPE="ed25519"
    readonly KEYS_DIR="$HOME/.ssh"
    readonly AUTH_KEYS_FILE="ssh-authorized-keys.conf"

    function generate_ssh_keys() {
      local -r key_name="$1"
      local -r key_password="$2"

      local -r key_file="$KEYS_DIR/$key_name"

      mkdir -p "$KEYS_DIR"
      chmod 700 "$KEYS_DIR"

      info "Generating new SSH key pair with password protection"
      ssh-keygen -t "$KEYTYPE" -f "$key_file" -C "$key_name" -N "$key_password" >&2

      echo "$key_file"
    }

    function export_keys() {
      local -r target="$1"
      local -r key_file="$2"

      info "Adding public key to $AUTH_KEYS_FILE"
      local -r pubkey=$(cat "$key_file.pub")
      echo "$target, admin, $pubkey" >> "$AUTH_KEYS_FILE"
    }

    function add_ssh_config_entry() {
      local -r target="$1"
      local -r key_file_path="$2"
      local -r ssh_config_path="$HOME/.ssh/config"

      # Create SSH config if it doesn't exist
      touch "$ssh_config_path"

      # Check if entry already exists
      if grep -q "^Host $target\$" "$ssh_config_path"; then
        info "SSH config entry for $target already exists, skipping"
        return
      fi

      # Add entry to SSH config
      info "Adding SSH config entry for $target"
      local -r config_entry=$(concat \
        "Host $target" \
        "  HostName $target.nb.krejci.io" \
        "  User admin" \
        "  IdentityFile $key_file_path"
      )

      echo "$config_entry" >> "$ssh_config_path"
    }

    function commit_keys() {
      local -r target="$1"
      local -r key_name="$2"

      info "Committing changes to $AUTH_KEYS_FILE"
      git add "$AUTH_KEYS_FILE"
      git commit -m "$target: Authorize $key_name ssh key"
    }

    function main() {
      [ $# -eq 1 ] || {
        error "Usage: add-ssh-key TARGET"
        exit 1
      }
      local -r target="$1"

      local -r hostname="$(hostname)"
      local -r username="$(whoami)"
      local -r key_name="$username-$hostname-$target"

      local -r key_password=$(ask_for_token "key password")
      local -r key_file=$(generate_ssh_keys "$key_name" "$key_password")
      export_keys "$target" "$key_file"
      add_ssh_config_entry "$target" "$key_file"
      commit_keys "$target" "$key_name"

      info "SSH key pair generated successfully"
    }

    main "$@"
  '';
}

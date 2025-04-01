{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "generate-ssh-key";
  runtimeInputs = with pkgs; [
    coreutils
    openssh
    gnused
    gnupg
  ];
  text = ''
    #!/usr/bin/env bash
    set -euo pipefail

    readonly KEYTYPE="ed25519"
    readonly KEYS_DIR="$HOME/.ssh"
    readonly AUTH_KEYS_FILE="ssh-authorized-keys.pub"

    # Ask for password with confirmation
    function ask_for_password() {
      while true; do
        echo -n "Enter key password: " >&2
        local key_password
        read -rs key_password
        echo >&2

        if [ -z "$key_password" ]; then
          echo "Password cannot be empty. Please try again." >&2
          continue
        fi

        echo -n "Confirm password: " >&2
        local key_password_confirm
        read -rs key_password_confirm
        echo >&2

        if [ "$key_password" = "$key_password_confirm" ]; then
          break
        fi
        echo "Passwords do not match. Please try again." >&2
      done

      echo -n "$key_password"
    }

    function generate_ssh_keys() {
      local -r key_name="$1"
      local -r key_password="$2"

      local -r key_file="$KEYS_DIR/$key_name"

      # Create .ssh directory if it doesn't exist
      mkdir -p "$KEYS_DIR"
      chmod 700 "$KEYS_DIR"

      # Generate the SSH key pair with password protection
      echo "Generating new SSH key pair with password protection" >&2
      ssh-keygen -t "$KEYTYPE" -f "$key_file" -C "$key_name" -N "$key_password" >&2

      echo "$key_file"
    }

    function export_keys() {
      local -r auth_keys_path="$1"
      local -r key_file="$2"

      # Ensure authorized keys file directory exists
      mkdir -p "$(dirname "$auth_keys_path")"

      # Add public key to authorized keys file
      echo "Adding public key to $auth_keys_path" >&2
      cat "$key_file.pub" >> "$auth_keys_path"
    }

    function commit_keys() {
      local -r auth_keys_path="$1"
      local -r target="$2"
      local -r username="$3"
      local -r hostname="$4"

      echo "Committing changes to $auth_keys_path" >&2
      git add "$auth_keys_path"
      git commit -m "$target: Authorize $username-$hostname ssh key"
    }

    function main() {
      if [ $# -ne 1 ]; then
        echo "Usage: add-ssh-key TARGET"
        exit 1
      fi
      local -r target="$1"

      local -r hostname="$(hostname)"
      local -r username="$(whoami)"

      local -r key_name="$username-$hostname-$target"
      local -r auth_keys_path="hosts/$target/$AUTH_KEYS_FILE"

      local -r key_password=$(ask_for_password)
      local -r key_file=$(generate_ssh_keys "$key_name" "$key_password")
      export_keys "$auth_keys_path" "$key_file"
      commit_keys "$auth_keys_path" "$target" "$username" "$hostname"

      echo "SSH key pair generated successfully"
    }

    main "$@"
  '';
}

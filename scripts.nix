{
  pkgs,
  nixos-anywhere ? null,
  ...
}: {
  generate-ssh-key =
    pkgs.writeShellApplication
    {
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
    };

  # Generate wireguard key pair and configuration
  # for non-NixOS system, e.g. cell phone.
  # `nix run .#wireguard-config hostname`
  wireguard-config =
    pkgs.writeShellApplication
    {
      name = "wireguard-config";
      runtimeInputs = with pkgs; [
        wireguard-tools
      ];
      text = ''
          #!/usr/bin/env bash
          set -euo pipefail

        if [ $# -ne 1 ]; then
          echo "Usage: wireguard HOSTNAME"
          exit 1
        fi

        HOSTNAME=$1

        SERVER_HOSTNAME="vpsfree"
        DOMAIN="vpn"

        # Get IP address and server key using nix eval
        IP_ADDRESS=$(nix eval --raw ".#hosts.$HOSTNAME.ipAddress")
        SERVER_PUBKEY=$(nix eval --raw ".#hosts.$SERVER_HOSTNAME.wgPublicKey")

        echo "Generating WireGuard configuration for $HOSTNAME with IP $IP_ADDRESS"

        # Generate new keys
        PRIVATE_KEY=$(wg genkey)
        PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

        # Check if host directory exists
        if [ ! -d "hosts/$HOSTNAME" ]; then
          echo "Directory hosts/$HOSTNAME does not exist"
          exit 1
        fi

        # Write public key to file
        echo "$PUBLIC_KEY" >"hosts/$HOSTNAME/wg-key.pub"
        echo "Public key written to hosts/$HOSTNAME/wg-key.pub"

        # Create config file
        CONFIG_DIR=$(mktemp -d)
        CONFIG_FILE="$CONFIG_DIR/wg0.conf"

        cat > "$CONFIG_FILE" << EOF
        [Interface]
        PrivateKey = $PRIVATE_KEY
        Address = $IP_ADDRESS
        DNS = 192.168.99.1, $DOMAIN

        [Peer]
        PublicKey = $SERVER_PUBKEY
        AllowedIPs = 192.168.99.0/24
        Endpoint = 37.205.13.227:51820
        EOF

        # Generate QR code
        ${pkgs.qrencode}/bin/qrencode -o "$CONFIG_DIR/wg0.png" < "$CONFIG_FILE"

        echo "Configuration generated at: $CONFIG_FILE"
        echo "QR code generated at: $CONFIG_DIR/wg0.png"
      '';
    };

  # Builds NixOS sdcard image that can be used for aarch64
  # Raspberry Pi machines.
  # `nix run .#build-sdcard hostname`
  build-sdcard =
    pkgs.writeShellApplication
    {
      name = "build-sdcard";
      runtimeInputs = with pkgs; [
        coreutils
        wireguard-tools
      ];
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        if [ $# -ne 1 ]; then
          echo "Usage: build-sdcard HOSTNAME"
          exit 1
        fi
        readonly HOSTNAME="$1"

        readonly IMAGE_NAME="$HOSTNAME-sdcard"

        # Create a temporary directory for the build
        echo "Generating WireGuard keys for $HOSTNAME..."
        TMP_DIR=$(mktemp -d)
        wg genkey > "$TMP_DIR/wg-key"
        wg pubkey < "$TMP_DIR/wg-key" > "hosts/$HOSTNAME/wg-key.pub"

        echo "Public key generated and saved to hosts/$HOSTNAME/wg-key.pub"
        echo "Building ISO image with embedded private key..."

        WG_PRIVATE_KEY=$(cat "$TMP_DIR/wg-key")
        export WG_PRIVATE_KEY

        echo "Building image for host: $HOSTNAME"

        # Build the image - clean and simple
        nix build ".#image.sdcard.$HOSTNAME" \
          --impure \
          -o "$IMAGE_NAME"

        echo "Image built successfully: $IMAGE_NAME"

        # Clean up private key
        shred -zu "$TMP_DIR//wg-key"
        rm -rf "$TMP_DIR"
        unset WG_PRIVATE_KEY

        echo "Private key securely deleted, build complete."
      '';
    };

  # Builds iso image for USB stick that can be used to boot
  # and install the NixOS system on x86-64 machine.
  build-installer =
    pkgs.writeShellApplication
    {
      name = "build-installer";
      runtimeInputs = with pkgs; [
        coreutils
        wireguard-tools
      ];
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        readonly HOSTNAME="iso"

        # Create a temporary directory for the build
        echo "Generating WireGuard keys for $HOSTNAME..."
        TMP_DIR=$(mktemp -d)
        wg genkey > "$TMP_DIR/wg-key"
        wg pubkey < "$TMP_DIR/wg-key" > "hosts/$HOSTNAME/wg-key.pub"

        echo "Public key generated and saved to hosts/$HOSTNAME/wg-key.pub"
        echo "Building ISO image with embedded private key..."

        WG_PRIVATE_KEY=$(cat "$TMP_DIR/wg-key")
        export WG_PRIVATE_KEY

        # Build the image using nixos-generators via flake output
        # Pass the temporary directory path to Nix
        nix build ".#image.installer" \
          --impure \
          -o "iso-image"

        echo "ISO image built successfully: iso-image"

        # Clean up private key
        shred -zu "$TMP_DIR//wg-key"
        rm -rf "$TMP_DIR"
        unset WG_PRIVATE_KEY

        echo "Private key securely deleted, build complete."
      '';
    };

  # Deploy changes remotely. It is expected that the host
  # is running the NixOS and is accessible over network.
  # `nix run .#deploy-config hostname`
  deploy-config =
    pkgs.writeShellApplication
    {
      name = "deploy-config";
      runtimeInputs = with pkgs; [
        deploy-rs
      ];
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        # Display usage information
        if [ $# -lt 1 ]; then
          echo "Usage: deploy HOSTNAME"
        fi

        readonly hostname="$1"
        shift

        # Run deploy-rs
        echo "Deploying to $hostname..."
        # TODO get rid of skip checks

        deploy \
          --skip-checks \
          ".#$hostname" "$@"
      '';
    };

  # Install nixos remotely. It is expected that the host
  # is booted via USB stick and accesible on iso.vpn
  # `nix run .#nixos-install`
  nixos-install =
    pkgs.writeShellApplication
    {
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
          while true; do
            echo -n "Enter disk encryption password: " >&2
            local disk_password
            read -rs disk_password
            echo >&2

            if [ -z "$disk_password" ]; then
              echo "Password cannot be empty. Please try again." >&2
              continue
            fi

            echo -n "Confirm password: " >&2
            local disk_password_confirm
            read -rs disk_password_confirm
            echo >&2

            if [ "$disk_password" = "$disk_password_confirm" ]; then
              break
            fi
            echo "Passwords do not match. Please try again." >&2
          done

          echo -n "$disk_password"
        }

        # Generate random password that can be changed later
        function generate_disk_password() {
          echo "Generating disk password" >&2

          local disk_password
          disk_password=$(head -c 12 /dev/urandom | base64 | tr -d '/+=' | head -c 16)

          echo -n "$disk_password"
        }

        function set_disk_password() {
          local generate_password
          echo -n "Auto-generate disk encryption password? [Y/n] " >&2
          read -r generate_password

          # Create temporary password file to be passed to nixos-anywhere
          local -r tmp_folder=$(mktemp -d)
          readonly LOCAL_DISK_PASSWORD_PATH="$tmp_folder/disk-password"

          local disk_password
          # Default to Yes if empty or starts with Y/y
          if [[ -z "$generate_password" || "$generate_password" =~ ^[Yy] ]]; then
            disk_password=$(generate_disk_password)
            echo "Disk password auto-generated." >&2
          else
            disk_password=$(ask_for_disk_password)
            echo "Disk password has been set." >&2
          fi

          echo -n "$disk_password" >"$LOCAL_DISK_PASSWORD_PATH"
          # Create the directory where TPM expects disk password during
          # the key enrollment, it will be removed after the fisrt boot
          install -d -m755 "$TEMP/$REMOTE_DISK_PASSWORD_FOLDER"
          cp "$LOCAL_DISK_PASSWORD_PATH" "$TEMP/$REMOTE_DISK_PASSWORD_FOLDER"

          echo "Disk password successfully installed." >&2
        }

        function generate_wg_key() {
          local -r hostname="$1"

          # Generate new wireguard keys
          echo "Generating wireguard key" >&2
          local -r wg_private_key=$(${pkgs.wireguard-tools}/bin/wg genkey)
          local -r wg_public_key=$(echo "$wg_private_key" | ${pkgs.wireguard-tools}/bin/wg pubkey)

          # Check if host directory exists
          local host_folder="hosts/$hostname"
          if [ ! -d "$host_folder" ]; then
            echo "Host directory $host_folder does not exist" >&2
            exit 1
          fi
          local -r pubkey_path="$host_folder/wg-key.pub"

          # Write public key to the host file
          echo "$wg_public_key" > "$pubkey_path"
          echo "Wireguard public key written to $pubkey_path" >&2

          # Create the directory where wiregusrd expects to find the private key
          install -d -m700 "$TEMP/$WG_KEY_FOLDER"
          echo "$wg_private_key" > "$TEMP/$WG_KEY_PATH"
          chmod 600 "$TEMP/$WG_KEY_PATH"
        }

        function main() {
          if [ $# -lt 1 ]; then
            echo "Usage: $0 hostname" >&2
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
    };
}

{
  pkgs,
  nixos-anywhere ? null,
  ...
}: let
  # Helper library with usefull functions
  lib = pkgs.writeShellScript "script-lib" ''
    function concat() {
      local IFS=$'\n'
      echo "$*"
    }

    function require_hostname() {
      if [ $# -eq 0 ]; then
        echo "Error: Hostname required"
        echo "Usage: $(basename "$0") HOSTNAME"
        exit 1
      fi
    }

    function validate_hostname() {
      local -r hostname="$1"
      if ! nix eval .#hosts."$hostname" &>/dev/null; then
        echo "Error: Unknown host '$hostname'"
        echo "Available hosts:"
        nix eval .#hosts --apply 'hosts: builtins.attrNames hosts' --json | jq -r '.[]' | sed 's/^/  - /'
        exit 1
      fi
    }

    # Ask for token with confirmation
    function ask_for_token() {
      local -r token_name="''${1:-password}"

      # Check if running in interactive terminal
      if [ ! -t 0 ]; then
        echo "ERROR: $token_name required but not running in interactive terminal" >&2
        exit 1
      fi

      while true; do
        echo -n "Enter $token_name: " >&2
        local token
        read -rs token
        echo >&2

        if [ -z "$token" ]; then
          echo "ERROR: $token_name cannot be empty" >&2
          continue
        fi

        echo -n "Confirm $token_name: " >&2
        local token_confirm
        read -rs token_confirm
        echo >&2

        if [ "$token" = "$token_confirm" ]; then
          break
        fi
        echo "ERROR: $token_name do not match. Please try again." >&2
      done

      echo -n "$token"
    }

    # Generate Netbird setup key via API
    # Usage: generate_netbird_key hostname [allow_extra_dns_labels]
    function generate_netbird_key() {
      local -r hostname="$1"
      local -r allow_extra_dns_labels="''${2:-false}"

      if [ -z "''${NETBIRD_API_TOKEN:-}" ]; then
        echo "NETBIRD_API_TOKEN not found in environment" >&2
        NETBIRD_API_TOKEN=$(ask_for_token "Netbird API token")
        export NETBIRD_API_TOKEN
      fi

      if [ -z "$NETBIRD_API_TOKEN" ]; then
        echo "ERROR: Netbird API token is required" >&2
        exit 1
      fi

      echo "Generating Netbird setup key for $hostname (allow_extra_dns_labels=$allow_extra_dns_labels)" >&2

      local request_body
      request_body=$(jq -n \
        --arg name "$hostname" \
        --argjson expires_in 86400 \
        --argjson usage_limit 1 \
        --argjson ephemeral false \
        --arg key_type "one-off" \
        --argjson allow_extra_dns "$allow_extra_dns_labels" \
        '{
          name: $name,
          type: $key_type,
          expires_in: $expires_in,
          auto_groups: [],
          usage_limit: $usage_limit,
          ephemeral: $ephemeral,
          allow_extra_dns_labels: $allow_extra_dns
        }')

      local api_response
      if ! api_response=$(curl -s -X POST https://api.netbird.io/api/setup-keys \
        -H "Authorization: Token $NETBIRD_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data-raw "$request_body" 2>&1); then
        echo "ERROR: Failed to create Netbird setup key via API" >&2
        echo "Response: $api_response" >&2
        exit 1
      fi

      local -r setup_key=$(echo "$api_response" | jq -r '.key')

      if [ -z "$setup_key" ] || [ "$setup_key" = "null" ]; then
        echo "ERROR: Netbird setup key is empty or invalid" >&2
        echo "API Response: $api_response" >&2
        exit 1
      fi

      echo -n "$setup_key"
    }

  '';
in {
  add-ssh-key =
    pkgs.writeShellApplication
    {
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
        readonly AUTH_KEYS_FILE="ssh-authorized-keys.pub"

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

        function add_ssh_config_entry() {
          local -r target="$1"
          local -r key_file_path="$2"
          local -r ssh_config_path="$HOME/.ssh/config"

          # Create SSH config if it doesn't exist
          touch "$ssh_config_path"

          # Check if entry already exists
          if grep -q "^Host $target\$" "$ssh_config_path"; then
            echo "SSH config entry for $target already exists, skipping" >&2
            return
          fi

          # Add entry to SSH config
          echo "Adding SSH config entry for $target" >&2
          local -r config_entry=$(concat \
            "Host $target" \
            "  HostName $target.x.nb" \
            "  User admin" \
            "  IdentityFile $key_file_path"
          )

          echo "$config_entry" >> "$ssh_config_path"
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

          local -r key_password=$(ask_for_token "key password")
          local -r key_file=$(generate_ssh_keys "$key_name" "$key_password")
          export_keys "$auth_keys_path" "$key_file"
          commit_keys "$auth_keys_path" "$target" "$username" "$hostname"

          echo "SSH key pair generated successfully"
        }

        main "$@"
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
        # shellcheck source=/dev/null
        source ${lib}

        require_hostname "$@"
        readonly HOSTNAME="$1"
        validate_hostname "$HOSTNAME"

        readonly IMAGE_NAME="$HOSTNAME-sdcard"

        echo "Building image for host: $HOSTNAME"

        # Build the image - clean and simple
        nix build ".#image.sdcard.$HOSTNAME" \
          -o "$IMAGE_NAME"

        echo "Image built successfully: $IMAGE_NAME"
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
        curl
        jq
      ];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        readonly HOSTNAME="iso"

        # Check if NETBIRD_API_TOKEN is set, prompt if not
        if [ -z "''${NETBIRD_API_TOKEN:-}" ]; then
          NETBIRD_API_TOKEN=$(ask_for_token "Netbird API token")

          if [ -z "$NETBIRD_API_TOKEN" ]; then
            echo "ERROR: Netbird API token is required" >&2
            exit 1
          fi

          export NETBIRD_API_TOKEN
        fi

        echo "Generating Netbird setup key for $HOSTNAME..."

        # Generate reusable setup key for ISO installer (ephemeral peers)
        # ISO can be booted multiple times, each boot creates ephemeral peer
        api_response=$(curl -s -X POST https://api.netbird.io/api/setup-keys \
          -H "Authorization: Token $NETBIRD_API_TOKEN" \
          -H "Content-Type: application/json" \
          --data-raw "{\"name\":\"$HOSTNAME\",\"type\":\"reusable\",\"expires_in\":2592000,\"auto_groups\":[],\"usage_limit\":0,\"ephemeral\":true}" 2>&1) || {
          echo "ERROR: Failed to create Netbird setup key via API" >&2
          echo "Response: $api_response" >&2
          exit 1
        }

        # Extract the key from the API response
        NETBIRD_SETUP_KEY=$(echo "$api_response" | jq -r '.key')

        # Validate that we got a non-empty key
        if [ -z "$NETBIRD_SETUP_KEY" ] || [ "$NETBIRD_SETUP_KEY" = "null" ]; then
          echo "ERROR: Netbird setup key is empty or invalid" >&2
          echo "API Response: $api_response" >&2
          exit 1
        fi

        export NETBIRD_SETUP_KEY

        # Build the image using nixos-generators via flake output
        # Pass the setup key via environment variable to Nix
        nix build ".#image.installer" \
          --impure \
          -o "iso-image"

        echo "ISO image built successfully: iso-image"

        # Clean up setup key
        unset NETBIRD_SETUP_KEY

        echo "Setup key securely deleted, build complete."
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
        openssh
      ];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        require_hostname "$@"

        readonly HOSTNAME="$1"
        shift

        validate_hostname "$HOSTNAME"

        # Run deploy-rs
        echo "Deploying to $HOSTNAME..."

        deploy \
          --skip-checks \
          ".#$HOSTNAME" "$@"

        # Workaround for deploy-rs issue #153: /run/current-system not updated
        # https://github.com/serokell/deploy-rs/issues/153
        echo "Updating /run/current-system symlink..."
        ssh "$HOSTNAME.krejci.io" "sudo ln -sfn /nix/var/nix/profiles/system /run/current-system"
        echo "Deployment complete!"
      '';
    };

  # Install nixos remotely. It is expected that the host
  # is booted via USB stick and accesible on iso.krejci.io
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
        iputils
        openssh
        jq
        curl
      ];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        trap cleanup EXIT INT TERM

        readonly TARGET="iso.krejci.io"
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

          echo "Disk password successfully installed." >&2
        }

        function install_netbird_key() {
          local -r hostname="$1"

          # Check if host has extra DNS labels configured
          local extra_dns_labels
          extra_dns_labels=$(nix eval ".#hosts.$hostname.extraDnsLabels" --json 2>/dev/null | jq -r 'length')

          local allow_extra_dns="false"
          if [ "$extra_dns_labels" -gt 0 ]; then
            allow_extra_dns="true"
          fi

          local -r setup_key=$(generate_netbird_key "$hostname" "$allow_extra_dns")

          # Create directory for Netbird setup key
          install -d -m755 "$TEMP/$NETBIRD_KEY_FOLDER"
          echo "$setup_key" > "$TEMP/$NETBIRD_KEY_PATH"
          chmod 600 "$TEMP/$NETBIRD_KEY_PATH"

          echo "Netbird setup key installed for $hostname" >&2
        }

        function check_target_reachable() {
          echo -n "Checking if $TARGET is reachable... "

          if ! ping -c 1 -W 2 "$TARGET" >/dev/null 2>&1; then
            echo "FAILED"
            exit 1
          fi
          echo "OK"
        }

        function check_ssh_connection() {
          echo -n "Checking SSH connection to $TARGET... "

          if ! ssh "admin@$TARGET" exit 2>/dev/null; then
            echo "FAILED"
            exit 1
          fi
          echo "OK"
        }

        function check_secure_boot_setup_mode() {
          echo -n "Checking secure boot setup mode... "

          if ssh "admin@$TARGET" \
            'sbctl status | grep -qE "Setup Mode:.*Enabled"' 2>/dev/null; then
            echo "OK"
            return
          fi

          echo "WARNING: Target secure boot not in Setup Mode"
          read -r -p "Continue anyway? [y/N] " response

          case "$response" in
            y|Y)
              ;;
            *)
              echo "Installation aborted"
              exit 1
              ;;
          esac

        }

        function main() {

          require_hostname "$@"
          local -r hostname="$1"
          validate_hostname "$hostname"

          check_target_reachable
          check_ssh_connection
          check_secure_boot_setup_mode

          set_disk_password

          install_netbird_key "$hostname"

          # Install NixOS to the host system with our secrets
          nixos-anywhere \
            --disk-encryption-keys "$REMOTE_DISK_PASSWORD_PATH" "$LOCAL_DISK_PASSWORD_PATH" \
            --extra-files "$TEMP" \
            --flake ".#$hostname" \
            --target-host "root@$TARGET"
        }

        main "$@"
      '';
    };

  # Inject Cloudflare API token to remote host for ACME certificates
  # `nix run .#inject-cloudflare-token hostname`
  inject-cloudflare-token =
    pkgs.writeShellApplication
    {
      name = "inject-cloudflare-token";
      runtimeInputs = with pkgs; [
        openssh
      ];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        require_hostname "$@"
        readonly HOSTNAME="$1"
        validate_hostname "$HOSTNAME"

        readonly DOMAIN="krejci.io"
        readonly USER="admin"
        readonly TARGET="$USER@$HOSTNAME.$DOMAIN"

        echo "Injecting Cloudflare token to $HOSTNAME..."

        # Ask for token once
        token=$(ask_for_token "Cloudflare API token")

        # Create the token file content
        token_content=$(concat \
          "CLOUDFLARE_DNS_API_TOKEN=$token" \
          "CF_ZONE_API_TOKEN=$token"
        )

        # Create directory
        ssh "$TARGET" "sudo mkdir -p /var/lib/acme"

        # Write token file
        echo "$token_content" | ssh "$TARGET" "sudo tee /var/lib/acme/cloudflare-api-token > /dev/null"

        # Set permissions
        ssh "$TARGET" "sudo chmod 600 /var/lib/acme/cloudflare-api-token"

        echo "Cloudflare token successfully injected to $HOSTNAME"

        # Restart ACME service to acquire certificate
        echo "Restarting ACME service to acquire certificate..."
        ssh "$TARGET" "sudo systemctl start acme-$DOMAIN.service"

        echo "Certificate acquisition initiated. Check status with: systemctl status acme-$DOMAIN.service"
      '';
    };

  # Re-enroll Netbird with new setup key (for adding extra DNS labels)
  # `nix run .#reenroll-netbird hostname`
  reenroll-netbird =
    pkgs.writeShellApplication
    {
      name = "reenroll-netbird";
      runtimeInputs = with pkgs; [
        coreutils
        openssh
        curl
        jq
      ];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        readonly DOMAIN="krejci.io"
        readonly NETBIRD_KEY_PATH="/var/lib/netbird-homelab/setup-key"

        function inject_setup_key() {
          local -r target="$1"
          local -r setup_key="$2"

          echo "Injecting setup key..."

          # Inject the key
          # shellcheck disable=SC2029 # NETBIRD_KEY_PATH intentionally expands on client side
          if ! echo "$setup_key" | ssh "$target" "sudo tee $NETBIRD_KEY_PATH > /dev/null"; then
            echo "ERROR: Failed to inject setup key via SSH" >&2
            echo "Check SSH connection and sudo permissions" >&2
            exit 1
          fi

          # Set permissions
          # shellcheck disable=SC2029 # NETBIRD_KEY_PATH intentionally expands on client side
          if ! ssh "$target" "sudo chmod 600 $NETBIRD_KEY_PATH"; then
            echo "ERROR: Failed to set permissions on setup key" >&2
            exit 1
          fi

          # Verify the key was injected
          # shellcheck disable=SC2029 # NETBIRD_KEY_PATH intentionally expands on client side
          if ! ssh "$target" "sudo test -f $NETBIRD_KEY_PATH"; then
            echo "ERROR: Setup key file does not exist after injection" >&2
            exit 1
          fi

          echo "Setup key injected and verified successfully"
        }

        function prepare_peer_removal() {
          local -r hostname="$1"

          echo ""
          echo "NEXT STEPS:"
          echo "1. Open Netbird dashboard and find peer '$hostname'"
          echo "2. When ready, press Enter to trigger enrollment"
          echo "3. You will have 60 seconds to remove the old peer"
          echo "4. Connection will be lost after triggering"
          echo ""
          read -r -p "Press Enter when ready to trigger enrollment..." _
        }

        function trigger_enrollment() {
          local -r target="$1"
          local -r hostname="$2"

          echo "Triggering enrollment service..."

          # Try to trigger enrollment - may fail if connection is already lost
          if ! ssh "$target" "sudo systemd-run --on-active=60 systemctl start netbird-homelab-enroll.service" 2>/dev/null; then
            echo "WARNING: Could not trigger enrollment via SSH (connection may be lost)"
            echo "The enrollment service should start automatically on next boot"
            echo ""
            read -r -p "Press Enter to continue..." _
            return 0
          fi

          echo "Enrollment scheduled to start in 60 seconds"
          echo ""
          echo "Remove old peer '$hostname' from dashboard NOW"
          echo ""
          read -r -p "Press Enter after removing peer..." _
        }

        function wait_for_host() {
          local -r target="$1"

          echo "Waiting for host to come back online..."
          echo "(This may take up to 2 minutes)"

          local attempts=0
          local max_attempts=60  # 2 minutes total

          while [ $attempts -lt $max_attempts ]; do
            if ssh -o ConnectTimeout=2 -o BatchMode=yes "$target" "exit" 2>/dev/null; then
              echo ""
              echo "Host is back online!"
              return 0
            fi

            attempts=$((attempts + 1))

            # Show elapsed time every 10 attempts, otherwise show dot
            local progress="."
            if [ $((attempts % 10)) -eq 0 ]; then
              progress=" $((attempts * 2))s"
            fi
            echo -n "$progress"

            sleep 2
          done

          echo ""
          echo "ERROR: Host did not come back online within $((max_attempts * 2)) seconds"
          echo "Check the host's console or Netbird dashboard to verify enrollment status"
          return 1
        }

        function main() {
          require_hostname "$@"
          local -r hostname="$1"
          validate_hostname "$hostname"

          local -r target="admin@$hostname.$DOMAIN"

          local -r setup_key=$(generate_netbird_key "$hostname" true)
          inject_setup_key "$target" "$setup_key"
          prepare_peer_removal "$hostname"
          trigger_enrollment "$target" "$hostname"
          wait_for_host "$target"

          echo ""
          echo "Re-enrollment complete! Verify new peer in dashboard."
        }

        main "$@"
      '';
    };

  # Inject Borg passphrase to both server and client
  # `nix run .#inject-borg-passphrase <server-host> <client-host>`
  inject-borg-passphrase =
    pkgs.writeShellApplication
    {
      name = "inject-borg-passphrase";
      runtimeInputs = with pkgs; [
        openssh
      ];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        if [ $# -ne 2 ]; then
          echo "Usage: inject-borg-passphrase <server-host> <client-host>"
          echo ""
          echo "Examples:"
          echo "  inject-borg-passphrase vpsfree thinkcenter  # remote backup"
          echo "  inject-borg-passphrase thinkcenter thinkcenter  # local backup"
          exit 1
        fi

        readonly SERVER_HOST="$1"
        readonly CLIENT_HOST="$2"
        readonly DOMAIN="krejci.io"
        readonly USER="admin"
        readonly REPO_PATH="/var/lib/borg-repos/immich"

        local TARGET="remote"
        if [ "$SERVER_HOST" = "$CLIENT_HOST" ]; then
          TARGET="local"
        fi

        passphrase=$(ask_for_token "Borg $TARGET passphrase")

        readonly SERVER_SSH="$USER@$SERVER_HOST.$DOMAIN"
        readonly CLIENT_SSH="$USER@$CLIENT_HOST.$DOMAIN"

        # Check if repository already exists
        echo "Initializing repository on $SERVER_HOST..."
        # Client-side expansion intended - variables resolved before SSH
        # shellcheck disable=SC2029
        if ssh "$SERVER_SSH" "[ -f $REPO_PATH/config ]"; then
          echo "Repository already exists, skipping initialization"
          exit 0
        fi

        # Initialize repository
        # Client-side expansion intended - passphrase must not leak to logs
        # shellcheck disable=SC2029
        ssh "$SERVER_SSH" \
          "export BORG_PASSPHRASE='$passphrase' && \
           sudo -E borg init --encryption=repokey-blake2 $REPO_PATH"
        echo "Repository initialized"

        # Inject passphrase to client (for backup job)
        echo "Injecting passphrase to $CLIENT_HOST..."
        # Client-side expansion intended - TARGET resolved before SSH
        # shellcheck disable=SC2029
        echo "$passphrase" | ssh "$CLIENT_SSH" \
          "sudo tee /root/secrets/borg-passphrase-$TARGET > /dev/null"

        # Client-side expansion intended - TARGET resolved before SSH
        # shellcheck disable=SC2029
        ssh "$CLIENT_SSH" \
          "sudo chmod 600 /root/secrets/borg-passphrase-$TARGET"

        echo "Done!"
      '';
    };

  # Inject ntfy token to Grafana
  # `nix run .#inject-ntfy-token hostname`
  inject-ntfy-token =
    pkgs.writeShellApplication
    {
      name = "inject-ntfy-token";
      runtimeInputs = with pkgs; [
        openssh
        coreutils
        openssl
      ];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        require_hostname "$@"
        readonly HOSTNAME="$1"
        validate_hostname "$HOSTNAME"

        readonly DOMAIN="krejci.io"
        readonly USER="admin"
        readonly TARGET="$USER@$HOSTNAME.$DOMAIN"

        echo "Setting up ntfy authentication for $HOSTNAME..."

        # Create/update ntfy user (generates random password, only tokens used for auth)
        echo "Creating ntfy user 'grafana'..."
        password=$(openssl rand -base64 32)
        # shellcheck disable=SC2029 # password intentionally expands on client side
        ssh "$TARGET" "printf '%s\n%s\n' '$password' '$password' | sudo ntfy user add --role=admin grafana 2>&1 || true"

        # Generate token
        echo "Generating ntfy token..."
        token=$(ssh "$TARGET" "sudo ntfy token add grafana" | grep -oP 'token \K[^ ]+')

        if [ -z "$token" ]; then
          echo "ERROR: Failed to generate token"
          exit 1
        fi

        echo "Token generated: $token"

        # Create configuration files
        echo "Creating token configuration..."
        ssh "$TARGET" "sudo mkdir -p /var/lib/grafana/secrets"

        # Create environment file for Grafana
        echo "NTFY_TOKEN=$token" | ssh "$TARGET" "sudo tee /var/lib/grafana/secrets/ntfy-token-env > /dev/null"
        ssh "$TARGET" "sudo chmod 600 /var/lib/grafana/secrets/ntfy-token-env"
        ssh "$TARGET" "sudo chown root:root /var/lib/grafana/secrets/ntfy-token-env"

        # Create YAML config file for alertmanager-ntfy
        yaml_content=$(concat \
          "ntfy:" \
          "  auth:" \
          "    token: $token"
        )
        echo "$yaml_content" | ssh "$TARGET" "sudo tee /var/lib/grafana/secrets/ntfy-token.yaml > /dev/null"
        ssh "$TARGET" "sudo chmod 600 /var/lib/grafana/secrets/ntfy-token.yaml"
        ssh "$TARGET" "sudo chown root:root /var/lib/grafana/secrets/ntfy-token.yaml"

        # Restart services
        echo "Restarting services..."
        ssh "$TARGET" "sudo systemctl restart grafana.service 2>/dev/null || echo 'Grafana will start on next deployment'"
        ssh "$TARGET" "sudo systemctl restart alertmanager-ntfy.service 2>/dev/null || echo 'alertmanager-ntfy will start on next deployment'"

        echo "✓ ntfy token successfully configured for $HOSTNAME"
        echo "✓ Grafana and Prometheus alerts will now use ntfy"
      '';
    };

  # Validate ssh-authorized-keys.conf is parseable
  validate-ssh-keys = pkgs.runCommand "validate-ssh-keys" {} ''
    cd ${./.}

    if [ ! -f ssh-authorized-keys.conf ]; then
      echo "ERROR: ssh-authorized-keys.conf not found"
      exit 1
    fi

    # Test parsing: skip comments/empty, extract hostname/user/key
    ${pkgs.gnugrep}/bin/grep -v "^#" ssh-authorized-keys.conf | \
      ${pkgs.gnugrep}/bin/grep -v "^[[:space:]]*$" | \
      while IFS=, read -r host user key; do
        # Trim whitespace
        host=$(echo "$host" | ${pkgs.coreutils}/bin/tr -d ' \t')
        user=$(echo "$user" | ${pkgs.coreutils}/bin/tr -d ' \t')

        if [ -z "$host" ] || [ -z "$user" ] || [ -z "$key" ]; then
          echo "ERROR: Invalid line (missing hostname, user, or key)"
          exit 1
        fi
      done

    echo "ssh-authorized-keys.conf is parseable"
    touch $out
  '';

  # Expose the shared library for testing
  inherit lib;

  # Tests for the shared library functions
  script-lib-test =
    pkgs.runCommand "script-lib-test" {
      buildInputs = with pkgs; [
        bash
        nix
        jq
      ];
    } ''
      set -euo pipefail

      # Create a test environment
      export HOME=$(mktemp -d)
      mkdir -p hosts/test-host
      mkdir -p hosts/another-host

      # Source the shared library
      source ${lib}

      echo "Running script library tests..."

      # Test require_hostname function
      test_require_hostname() {
        echo "Testing require_hostname..."

        # Test with no arguments (should fail)
        set +e
        (require_hostname >/dev/null 2>&1)
        local exit_code=$?
        set -e
        if [ $exit_code -ne 1 ]; then
          echo "ERROR: require_hostname should fail with no arguments"
          return 1
        fi

        # Test with arguments (should pass)
        require_hostname "test-host"

        echo "✓ require_hostname tests passed"
      }

      # Run all tests
      test_require_hostname

      echo "All tests passed!"
      touch $out
    '';
}

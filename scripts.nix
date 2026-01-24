{
  pkgs,
  nixos-anywhere,
  ...
}: let
  lib = import ./scripts/lib.nix {inherit pkgs;};
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
        curl
        jq
      ];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        function configure_wifi() {
          get_wifi_from_sops && {
            info "Using WiFi credentials from secrets.yaml for $WIFI_SSID"
            return
          }

          # Not in interactive terminal, skip WiFi
          [ -t 0 ] || {
            info "No WiFi in secrets.yaml and not interactive, skipping"
            return
          }

          read -r -p "Configure WiFi? [y/N] " response
          case "$response" in
            y|Y) ;;
            *) info "Skipping WiFi configuration"; return ;;
          esac

          WIFI_SSID=$(ask_for_token "WiFi SSID")
          export WIFI_SSID

          WIFI_PASSWORD=$(ask_for_token "WiFi password")
          export WIFI_PASSWORD

          info "WiFi credentials set for $WIFI_SSID"
        }

        function main() {
          local -r hostname=$(require_and_validate_hostname "$@")
          local -r image_name="$hostname-sdcard"

          NETBIRD_SETUP_KEY=$(generate_netbird_key "$hostname")
          export NETBIRD_SETUP_KEY

          configure_wifi

          info "Building image for host: $hostname"

          nix build ".#image.sdcard.$hostname" \
            --impure \
            -o "$image_name"

          info "Image built successfully: $image_name"

          unset NETBIRD_SETUP_KEY WIFI_SSID WIFI_PASSWORD
          info "Secrets cleared, build complete"
        }

        main "$@"
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

        function main() {
          local -r hostname="iso"

          NETBIRD_SETUP_KEY=$(generate_netbird_key "$hostname" --reusable)
          export NETBIRD_SETUP_KEY

          # Build the image using nixos-generators via flake output
          # Pass the setup key via environment variable to Nix
          nix build ".#image.installer" \
            --impure \
            -o "iso-image"

          info "ISO image built successfully: iso-image"

          unset NETBIRD_SETUP_KEY
          info "Setup key securely deleted, build complete"
        }

        main "$@"
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
        nix
      ];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        readonly DOMAIN="nb.krejci.io"

        function main() {
          local -r hostname=$(require_and_validate_hostname "$@")
          local -r target="admin@$hostname.$DOMAIN"
          shift

          require_ssh_reachable "$target"

          info "Deploying to $hostname"

          deploy \
            --skip-checks \
            ".#$hostname" "$@"

          info "Deployment complete"
        }

        main "$@"
      '';
    };

  # Install nixos remotely. It is expected that the host
  # is booted via USB stick and accesible on iso.nb.krejci.io
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

        readonly DOMAIN="krejci.io"
        readonly PEER_DOMAIN="nb.krejci.io"
        readonly TOKEN_PATH="/var/lib/acme/cloudflare-api-token"

        function main() {
          local -r hostname=$(require_and_validate_hostname "$@")
          local -r target="admin@$hostname.$PEER_DOMAIN"

          require_ssh_reachable "$target"

          info "Injecting Cloudflare token to $hostname"

          local -r token=$(ask_for_token "Cloudflare API token")
          local -r token_content=$(concat \
            "CLOUDFLARE_DNS_API_TOKEN=$token" \
            "CF_ZONE_API_TOKEN=$token"
          )

          inject_secret \
            --target "$target" \
            --path "$TOKEN_PATH" \
            --content "$token_content"

          info "Cloudflare token successfully injected to $hostname"

          info "Restarting ACME service to acquire certificate"
          # shellcheck disable=SC2029 # DOMAIN intentionally expands on client side
          ssh "$target" "sudo systemctl start acme-$DOMAIN.service"

          info "Certificate acquisition initiated. Check status with: systemctl status acme-$DOMAIN.service"
        }

        main "$@"
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

        readonly DOMAIN="nb.krejci.io"
        readonly NETBIRD_KEY_PATH="/var/lib/netbird-homelab/setup-key"

        function prepare_peer_removal() {
          local -r hostname="$1"

          info "NEXT STEPS:"
          info "1. Open Netbird dashboard and find peer '$hostname'"
          info "2. When ready, press Enter to trigger enrollment"
          info "3. You will have 60 seconds to remove the old peer"
          info "4. Connection will be lost after triggering"
          read -r -p "Press Enter when ready to trigger enrollment..." _
        }

        function trigger_enrollment() {
          local -r target="$1"
          local -r hostname="$2"

          info "Triggering enrollment service"

          # Try to trigger enrollment - may fail if connection is already lost
          if ! ssh "$target" "sudo systemd-run --on-active=60 systemctl start netbird-homelab-enroll.service" 2>/dev/null; then
            warn "Could not trigger enrollment via SSH (connection may be lost)"
            info "The enrollment service should start automatically on next boot"
            read -r -p "Press Enter to continue..." _
            return 0
          fi

          info "Enrollment scheduled to start in 60 seconds"
          warn "Remove old peer '$hostname' from dashboard NOW"
          read -r -p "Press Enter after removing peer..." _
        }

        function wait_for_host() {
          local -r target="$1"

          info "Waiting for host to come back online (up to 2 minutes)"

          local attempts=0
          local max_attempts=60  # 2 minutes total

          while [ $attempts -lt $max_attempts ]; do
            if ssh -o ConnectTimeout=2 -o BatchMode=yes "$target" "exit" 2>/dev/null; then
              info "Host is back online"
              return 0
            fi

            attempts=$((attempts + 1))

            # Show elapsed time every 10 attempts, otherwise show dot
            local progress="."
            if [ $((attempts % 10)) -eq 0 ]; then
              progress=" $((attempts * 2))s"
            fi
            echo -n "$progress" >&2

            sleep 2
          done

          error "Host did not come back online within $((max_attempts * 2)) seconds"
          info "Check the host's console or Netbird dashboard to verify enrollment status"
          return 1
        }

        function main() {
          local -r hostname=$(require_and_validate_hostname "$@")
          local -r target="admin@$hostname.$DOMAIN"

          require_ssh_reachable "$target"

          local -r setup_key=$(generate_netbird_key "$hostname")
          inject_secret \
            --target "$target" \
            --path "$NETBIRD_KEY_PATH" \
            --content "$setup_key"
          prepare_peer_removal "$hostname"
          trigger_enrollment "$target" "$hostname"
          wait_for_host "$target"

          info "Re-enrollment complete. Verify new peer in dashboard."
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

        readonly DOMAIN="nb.krejci.io"
        readonly REPO_PATH="/var/lib/borg-repos/immich"

        function init_repository() {
          local -r server_target="$1"
          local -r passphrase="$2"

          # Client-side expansion intended - passphrase must not leak to logs
          # shellcheck disable=SC2029
          ssh "$server_target" \
            "export BORG_PASSPHRASE='$passphrase' && \
             sudo -E borg init --encryption=repokey-blake2 $REPO_PATH"
        }

        function main() {
          if [ $# -ne 2 ]; then
            error "Usage: inject-borg-passphrase <server-host> <client-host>"
            info "Examples:"
            info "  inject-borg-passphrase vpsfree thinkcenter  # remote backup"
            info "  inject-borg-passphrase thinkcenter thinkcenter  # local backup"
            exit 1
          fi

          local -r server_host="$1"
          local -r client_host="$2"

          local backup_type="remote"
          [ "$server_host" = "$client_host" ] && backup_type="local"

          local -r passphrase=$(ask_for_token "Borg $backup_type passphrase")
          local -r server_target="admin@$server_host.$DOMAIN"
          local -r client_target="admin@$client_host.$DOMAIN"

          require_ssh_reachable "$server_target"
          require_ssh_reachable "$client_target"

          # Check if repository already exists
          info "Checking repository on $server_host"
          local repo_exists=false
          # shellcheck disable=SC2029 # REPO_PATH intentionally expands on client side
          ssh "$server_target" "[ -f $REPO_PATH/config ]" && repo_exists=true

          if [ "$repo_exists" = false ]; then
            init_repository "$server_target" "$passphrase"
            info "Repository initialized"
          fi

          info "Injecting passphrase to $client_host"
          inject_secret \
            --target "$client_target" \
            --path "/root/secrets/borg-passphrase-$backup_type" \
            --content "$passphrase"

          info "Done"
        }

        main "$@"
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

        readonly DOMAIN="nb.krejci.io"
        readonly TOKEN_ENV_PATH="/var/lib/grafana/secrets/ntfy-token-env"
        readonly TOKEN_TXT_PATH="/var/lib/alertmanager/secrets/ntfy-token.txt"

        function create_ntfy_user() {
          local -r target="$1"

          info "Creating ntfy user 'grafana'"
          local -r password=$(openssl rand -base64 32)
          # shellcheck disable=SC2029 # password intentionally expands on client side
          ssh "$target" "printf '%s\n%s\n' '$password' '$password' | sudo ntfy user add --role=admin grafana 2>&1 || true"
        }

        function generate_ntfy_token() {
          local -r target="$1"

          info "Generating ntfy token"
          local token
          token=$(ssh "$target" "sudo ntfy token add grafana" | grep -oP 'token \K[^ ]+')

          if [ -z "$token" ]; then
            error "Failed to generate token"
            exit 1
          fi

          echo -n "$token"
        }

        function write_token_configs() {
          local -r target="$1"
          local -r token="$2"

          info "Creating token configuration"

          # Environment file for Grafana
          inject_secret \
            --target "$target" \
            --path "$TOKEN_ENV_PATH" \
            --content "NTFY_TOKEN=$token"

          # Plain text file for Alertmanager credentials_file
          inject_secret \
            --target "$target" \
            --path "$TOKEN_TXT_PATH" \
            --content "$token"
        }

        function restart_services() {
          local -r target="$1"

          info "Restarting services"
          ssh "$target" "sudo systemctl restart grafana.service 2>/dev/null || echo 'Grafana will start on next deployment'"
          ssh "$target" "sudo systemctl restart alertmanager.service 2>/dev/null || echo 'Alertmanager will start on next deployment'"
        }

        function main() {
          local -r hostname=$(require_and_validate_hostname "$@")
          local -r target="admin@$hostname.$DOMAIN"

          require_ssh_reachable "$target"

          info "Setting up ntfy authentication for $hostname"

          create_ntfy_user "$target"
          local -r token=$(generate_ntfy_token "$target")

          write_token_configs "$target" "$token"
          restart_services "$target"

          info "ntfy token successfully configured for $hostname"
        }

        main "$@"
      '';
    };

  # Inject Dex OAuth client secrets for all services
  # `nix run .#inject-dex-secrets hostname`
  #
  # Creates secrets for Dex and downstream services. Immich config is handled
  # declaratively in immich.nix via systemd preStart, not here.
  inject-dex-secrets =
    pkgs.writeShellApplication
    {
      name = "inject-dex-secrets";
      runtimeInputs = with pkgs; [openssh openssl];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        readonly PEER_DOMAIN="nb.krejci.io"
        readonly DEX_ISSUER="https://dex.krejci.io"
        readonly DEX_SECRETS_DIR="/var/lib/dex/secrets"
        readonly DEX_GOOGLE_OAUTH_FILE="$DEX_SECRETS_DIR/google-oauth"
        readonly GRAFANA_SECRETS_DIR="/var/lib/grafana/secrets"
        readonly DEX_CLIENTS=(grafana immich memos jellyfin)

        function require_google_oauth() {
          local -r target="$1"
          # Variables expand locally before SSH to build remote command
          # shellcheck disable=SC2029
          ssh "$target" "[ -f $DEX_GOOGLE_OAUTH_FILE ]" && return
          warn "Create $DEX_GOOGLE_OAUTH_FILE with GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET first"
          exit 1
        }

        function generate_client_secrets() {
          local -r target="$1"
          for client in "''${DEX_CLIENTS[@]}"; do
            local secret_file="$DEX_SECRETS_DIR/$client-client-secret"
            # Variables expand locally before SSH to build remote command
            # shellcheck disable=SC2029
            ssh "$target" "[ -f $secret_file ]" && { info "$client secret exists"; continue; }
            # Each service owns its secret so preStart can read it
            inject_secret \
              --target "$target" \
              --path "$secret_file" \
              --content "$(openssl rand -hex 32)" \
              --owner "$client:$client"
          done
        }

        function configure_grafana() {
          local -r target="$1"
          local -r dex_grafana_secret="$DEX_SECRETS_DIR/grafana-client-secret"
          local -r grafana_dex_secret="$GRAFANA_SECRETS_DIR/dex-client-secret"
          # Variables expand locally before SSH to build remote command
          # shellcheck disable=SC2029
          ssh "$target" "sudo mkdir -p $GRAFANA_SECRETS_DIR && \
            sudo cp $dex_grafana_secret $grafana_dex_secret && \
            sudo chown grafana:grafana $grafana_dex_secret"
          info "Grafana secret configured"
        }

        function print_memos_instructions() {
          local -r target="$1"
          local -r dex_memos_secret="$DEX_SECRETS_DIR/memos-client-secret"
          # Variables expand locally before SSH to build remote command
          # shellcheck disable=SC2029
          local -r secret=$(ssh "$target" "sudo cat $dex_memos_secret")
          info "Memos: configure manually in Settings → SSO"
          echo "  Client ID: memos"
          echo "  Client Secret: $secret"
          echo "  Issuer URL: $DEX_ISSUER"
        }

        function print_jellyfin_instructions() {
          local -r target="$1"
          local -r dex_jellyfin_secret="$DEX_SECRETS_DIR/jellyfin-client-secret"
          # Variables expand locally before SSH to build remote command
          # shellcheck disable=SC2029
          local -r secret=$(ssh "$target" "sudo cat $dex_jellyfin_secret")
          info "Jellyfin: install SSO plugin, then configure in Dashboard → Plugins → SSO"
          echo "  Provider Name: dex"
          echo "  OID Endpoint: $DEX_ISSUER"
          echo "  Client ID: jellyfin"
          echo "  Client Secret: $secret"
          echo "  Enabled: checked"
        }

        function main() {
          local -r hostname=$(require_and_validate_hostname "$@")
          local -r target="admin@$hostname.$PEER_DOMAIN"
          require_ssh_reachable "$target"

          require_google_oauth "$target"
          generate_client_secrets "$target"
          configure_grafana "$target"
          print_memos_instructions "$target"
          print_jellyfin_instructions "$target"
        }

        main "$@"
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

  # Import Google Keep notes to Memos with preserved timestamps
  # `nix run .#import-keep https://memos.example.com TOKEN ~/Keep`
  import-keep = pkgs.callPackage ./pkgs/import-keep {};

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

{
  pkgs,
  nixos-anywhere,
  ...
}: let
  # Helper library with useful functions
  lib = pkgs.writeShellScript "script-lib" ''
    function concat() {
      local IFS=$'\n'
      echo "$*"
    }

    # Enable color variables for terminal output
    # Colors only enabled when stderr is a TTY and NO_COLOR is unset
    # See: https://no-color.org/
    function setup_colors() {
      if [ -t 2 ] && [ -z "''${NO_COLOR:-}" ]; then
        RED=$'\033[0;31m'
        GREEN=$'\033[0;32m'
        ORANGE=$'\033[0;33m'
        BLUE=$'\033[0;34m'
        NC=$'\033[0m'
      else
        RED=""
        GREEN=""
        ORANGE=""
        BLUE=""
        NC=""
      fi
    }

    # Print timestamped message to stderr with optional level
    function message() {
      local level="''${1:-}"
      shift || true
      local timestamp
      timestamp=$(date -Iseconds)
      if [ -n "$level" ]; then
        echo "''${timestamp} ''${level} $*" >&2
      else
        echo "''${timestamp} $*" >&2
      fi
    }

    # Log INFO level (green)
    function info() {
      message "''${GREEN}INFO ''${NC}" "$@"
    }

    # Log WARN level (orange)
    function warn() {
      message "''${ORANGE}WARN ''${NC}" "$@"
    }

    # Log ERROR level (red)
    function error() {
      message "''${RED}ERROR''${NC}" "$@"
    }

    # Log DEBUG level (blue)
    function debug() {
      message "''${BLUE}DEBUG''${NC}" "$@"
    }

    # Initialize colors by default
    setup_colors

    function require_hostname() {
      if [ $# -eq 0 ]; then
        error "Hostname required"
        info "Usage: $(basename "$0") HOSTNAME"
        exit 1
      fi
    }

    function validate_hostname() {
      local -r hostname="$1"
      if ! nix eval .#hosts."$hostname" &>/dev/null; then
        error "Unknown host '$hostname'"
        info "Available hosts:"
        nix eval .#hosts --apply 'hosts: builtins.attrNames hosts' --json | jq -r '.[]' | sed 's/^/  - /' >&2
        exit 1
      fi
      info "Hostname '$hostname' validated"
    }

    # Check if host uses netbird-homelab for setup key enrollment.
    # Desktops use netbird-user with SSO login and do not need setup keys.
    function host_needs_netbird_key() {
      local -r hostname="$1"
      local modules
      modules=$(nix eval ".#hosts.$hostname.extraModules" --json 2>/dev/null) || return 1
      echo "$modules" | jq -e 'any(. | tostring; contains("netbird-homelab"))' >/dev/null
    }

    # Require and validate hostname, echo it on success
    # Usage: local -r hostname=$(require_and_validate_hostname "$@")
    function require_and_validate_hostname() {
      local -r hostname="$1"
      require_hostname "$hostname"
      validate_hostname "$hostname"
      echo "$hostname"
    }

    # Check if target is reachable via ping and SSH
    # Usage: require_ssh_reachable "admin@hostname.domain"
    function require_ssh_reachable() {
      local -r target="$1"
      local -r host=$(echo "$target" | cut -d'@' -f2)

      info "Checking if $host is reachable"
      if ! ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
        error "Target $host is not reachable"
        exit 1
      fi

      info "Checking SSH connection to $target"
      if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$target" exit 2>/dev/null; then
        error "SSH connection to $target failed"
        exit 1
      fi
      info "SSH connection to $target successful"
    }

    # Inject secret file to remote host via SSH
    # Usage: inject_secret --target user@host --path /path --content "data" [--mode 600] [--owner root:root]
    function inject_secret() {
      local target="" path="" content="" mode="600" owner="root:root"

      while [ $# -gt 0 ]; do
        case "$1" in
          --target) target="$2"; shift ;;
          --path) path="$2"; shift ;;
          --content) content="$2"; shift ;;
          --mode) mode="$2"; shift ;;
          --owner) owner="$2"; shift ;;
          *) error "inject_secret: unknown option $1"; exit 1 ;;
        esac
        shift
      done

      if [ -z "$target" ] || [ -z "$path" ] || [ -z "$content" ]; then
        error "inject_secret: --target, --path, and --content are required"
        exit 1
      fi

      local -r dir=$(dirname "$path")
      # shellcheck disable=SC2029 # variables intentionally expand on client side
      ssh "$target" "sudo mkdir -p $dir" || {
        error "inject_secret: failed to create directory $dir on $target"
        exit 1
      }
      echo "$content" | ssh "$target" "sudo tee $path > /dev/null" || {
        error "inject_secret: failed to write $path on $target"
        exit 1
      }
      ssh "$target" "sudo chmod $mode $path && sudo chown $owner $path" || {
        error "inject_secret: failed to set permissions on $path"
        exit 1
      }
      info "Secret injected to $target:$path"
    }

    # Ask for token with confirmation
    function ask_for_token() {
      local -r token_name="''${1:-password}"

      # Check if running in interactive terminal
      if [ ! -t 0 ]; then
        error "$token_name required but not running in interactive terminal"
        exit 1
      fi

      while true; do
        echo -n "Enter $token_name: " >&2
        local token
        read -rs token
        echo >&2

        if [ -z "$token" ]; then
          error "$token_name cannot be empty"
          continue
        fi

        echo -n "Confirm $token_name: " >&2
        local token_confirm
        read -rs token_confirm
        echo >&2

        if [ "$token" = "$token_confirm" ]; then
          break
        fi
        error "$token_name do not match. Please try again."
      done

      info "$token_name received"
      echo -n "$token"
    }

    # Try to get Netbird API token from sops secrets file
    function get_netbird_token_from_sops() {
      local -r secrets_file="secrets.yaml"
      [ -f "$secrets_file" ] || return 1

      local token
      token=$(${pkgs.sops}/bin/sops -d --extract '["netbird"]["api_token"]' "$secrets_file" 2>/dev/null) || return 1
      [ -n "$token" ] || return 1

      echo -n "$token"
    }

    # Try to get WiFi credentials from sops secrets file
    function get_wifi_from_sops() {
      local -r secrets_file="secrets.yaml"
      [ -f "$secrets_file" ] || return 1

      local ssid password
      ssid=$(${pkgs.sops}/bin/sops -d --extract '["wifi"]["ssid"]' "$secrets_file" 2>/dev/null) || return 1
      password=$(${pkgs.sops}/bin/sops -d --extract '["wifi"]["password"]' "$secrets_file" 2>/dev/null) || return 1
      [ -n "$ssid" ] && [ -n "$password" ] || return 1

      WIFI_SSID="$ssid"
      WIFI_PASSWORD="$password"
      export WIFI_SSID WIFI_PASSWORD
    }

    # Ensure NETBIRD_API_TOKEN is set, trying sops then interactive prompt
    function require_netbird_token() {
      [ -n "''${NETBIRD_API_TOKEN:-}" ] && return

      NETBIRD_API_TOKEN=$(get_netbird_token_from_sops) && {
        info "Using Netbird API token from secrets.yaml"
        export NETBIRD_API_TOKEN
        return
      }

      warn "NETBIRD_API_TOKEN not found in environment or secrets.yaml"
      NETBIRD_API_TOKEN=$(ask_for_token "Netbird API token")
      export NETBIRD_API_TOKEN
    }

    # Generate Netbird setup key via API
    # Usage: generate_netbird_key hostname [--reusable] [--allow-extra-dns]
    #   --reusable: Create reusable ephemeral key (for ISO installer)
    #   --allow-extra-dns: Allow extra DNS labels for this peer
    function generate_netbird_key() {
      local hostname=""
      local reusable=false
      local allow_extra_dns=false

      while [ $# -gt 0 ]; do
        case "$1" in
          --reusable) reusable=true ;;
          --allow-extra-dns) allow_extra_dns=true ;;
          *) hostname="$1" ;;
        esac
        shift
      done

      [ -n "$hostname" ] || {
        error "generate_netbird_key: hostname required"
        exit 1
      }

      require_netbird_token

      [ -n "$NETBIRD_API_TOKEN" ] || {
        error "Netbird API token is required"
        exit 1
      }

      local key_type="one-off"
      local ephemeral=false
      local usage_limit=1

      if [ "$reusable" = true ]; then
        key_type="reusable"
        ephemeral=true
        usage_limit=0
      fi

      info "Generating Netbird setup key for $hostname (type=$key_type, allow_extra_dns=$allow_extra_dns)"

      local request_body
      request_body=$(jq -n \
        --arg name "$hostname" \
        --argjson expires_in 2592000 \
        --argjson usage_limit "$usage_limit" \
        --argjson ephemeral "$ephemeral" \
        --arg key_type "$key_type" \
        --argjson allow_extra_dns "$allow_extra_dns" \
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
        error "Failed to create Netbird setup key via API"
        error "Response: $api_response"
        exit 1
      fi

      local -r setup_key=$(echo "$api_response" | jq -r '.key')

      if [ -z "$setup_key" ] || [ "$setup_key" = "null" ]; then
        error "Netbird setup key is empty or invalid"
        error "API Response: $api_response"
        exit 1
      fi

      info "Netbird setup key generated for $hostname"
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
          info "Generating new SSH key pair with password protection"
          ssh-keygen -t "$KEYTYPE" -f "$key_file" -C "$key_name" -N "$key_password" >&2

          echo "$key_file"
        }

        function export_keys() {
          local -r auth_keys_path="$1"
          local -r key_file="$2"

          # Ensure authorized keys file directory exists
          mkdir -p "$(dirname "$auth_keys_path")"

          # Add public key to authorized keys file
          info "Adding public key to $auth_keys_path"
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
            info "SSH config entry for $target already exists, skipping"
            return
          fi

          # Add entry to SSH config
          info "Adding SSH config entry for $target"
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

          info "Committing changes to $auth_keys_path"
          git add "$auth_keys_path"
          git commit -m "$target: Authorize $username-$hostname ssh key"
        }

        function main() {
          if [ $# -ne 1 ]; then
            error "Usage: add-ssh-key TARGET"
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
        readonly TOKEN_TXT_PATH="/var/lib/alertmanager/ntfy-token.txt"

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

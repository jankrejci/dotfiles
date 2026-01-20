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

  # Simplified secret injection script
  #
  # Each service declares secrets via homelab.secrets with:
  # - generate: how to create the value (token or ask)
  # - handler: script that receives secret on stdin, writes it, and restarts service
  # - username: ID for registration with central service (if register is set)
  # - register: central service to register with (ntfy or dex)
  #
  # Usage:
  #   nix run .#inject-secrets -- --host thinkcenter --secret alertmanager-ntfy
  #   nix run .#inject-secrets -- --host thinkcenter --all
  #   nix run .#inject-secrets -- --host thinkcenter --list
  inject-secrets =
    pkgs.writeShellApplication
    {
      name = "inject-secrets";
      runtimeInputs = with pkgs; [openssh openssl jq nix];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        readonly PEER_DOMAIN="nb.krejci.io"

        DRY_RUN=false

        function usage() {
          echo "Usage: inject-secrets --host <hostname> <--secret <name>|--all|--list> [--dry-run]" >&2
          echo "" >&2
          echo "Options:" >&2
          echo "  --host <name>    Target host" >&2
          echo "  --secret <name>  Inject a single secret" >&2
          echo "  --all            Inject all secrets for the host" >&2
          echo "  --list           List available secrets" >&2
          echo "  --dry-run        Show what would be done without doing it" >&2
          exit 1
        }

        function build_manifest() {
          local -r hostname="$1"

          info "Building secrets manifest for $hostname"
          local manifest_path
          manifest_path=$(nix build ".#nixosConfigurations.$hostname.config.system.build.secrets-manifest" --print-out-paths 2>/dev/null) || {
            error "Failed to build secrets manifest"
            info "This host may not have any secrets declared"
            exit 1
          }

          cat "$manifest_path"
        }

        function list_secrets() {
          local -r manifest="$1"

          echo "Available secrets:" >&2
          echo "$manifest" | jq -r 'to_entries[] | "  \(.key): register=\(.value.register // "none")"'
        }

        function secret_exists() {
          local -r manifest="$1"
          local -r secret_name="$2"

          echo "$manifest" | jq -e --arg name "$secret_name" 'has($name)' >/dev/null
        }

        # Find which host runs a central service like ntfy or dex.
        # Returns the hostname or exits with error if not found.
        function find_service_host() {
          local -r service_name="$1"

          # Eval flake to find host with service enabled
          local host
          host=$(nix eval ".#hosts" --json 2>/dev/null | jq -r --arg svc "$service_name" '
            to_entries[]
            | select(.value.homelab[$svc].enable == true)
            | .key
          ' | head -1)

          if [ -z "$host" ] || [ "$host" = "null" ]; then
            error "No host found with $service_name.enable = true"
            exit 1
          fi

          echo "$host"
        }

        # Get the register handler path for a central service
        function get_register_handler() {
          local -r service_name="$1"
          local -r service_host="$2"

          local handler_path
          handler_path=$(nix eval ".#nixosConfigurations.$service_host.config.homelab.$service_name.registerHandler" --raw 2>/dev/null) || {
            error "Failed to get $service_name.registerHandler from $service_host"
            exit 1
          }

          echo "$handler_path"
        }

        function inject_single_secret() {
          local -r hostname="$1"
          local -r manifest="$2"
          local -r secret_name="$3"

          if ! secret_exists "$manifest" "$secret_name"; then
            error "Secret '$secret_name' not found in manifest"
            list_secrets "$manifest"
            exit 1
          fi

          local generate_type handler_path username register_service
          generate_type=$(echo "$manifest" | jq -r --arg name "$secret_name" '.[$name].generate')
          handler_path=$(echo "$manifest" | jq -r --arg name "$secret_name" '.[$name].handler')
          username=$(echo "$manifest" | jq -r --arg name "$secret_name" '.[$name].username // empty')
          register_service=$(echo "$manifest" | jq -r --arg name "$secret_name" '.[$name].register // empty')

          info "Injecting secret: $secret_name"
          info "  Generate: $generate_type"
          info "  Handler: $handler_path"
          [ -n "$username" ] && info "  Username: $username"
          [ -n "$register_service" ] && info "  Register: $register_service"

          if [ "$DRY_RUN" = true ]; then
            echo "[dry-run] Would generate/prompt for secret and run handler" >&2
            [ -n "$register_service" ] && echo "[dry-run] Would register with $register_service" >&2
            return
          fi

          # Generate or prompt for the secret value
          local token
          case "$generate_type" in
            token)
              token=$(openssl rand -hex 32)
              ;;
            ask)
              echo "Enter value for $secret_name:" >&2
              read -rs token
              echo >&2
              if [[ -z "$token" ]]; then
                error "Empty value provided"
                exit 1
              fi
              ;;
            *)
              error "Unknown generate type: $generate_type"
              exit 1
              ;;
          esac

          local -r target="admin@$hostname.$PEER_DOMAIN"

          # Run the local handler to write the secret
          info "Running handler on $hostname"
          # shellcheck disable=SC2029 # store path expands client-side, glob expands server-side
          echo "$token" | ssh "$target" "sudo $handler_path/bin/*" || {
            error "Handler failed on $hostname"
            exit 1
          }

          # If registration is needed, run the central service's register handler
          if [ -n "$register_service" ] && [ -n "$username" ]; then
            local register_host register_handler
            register_host=$(find_service_host "$register_service")
            register_handler=$(get_register_handler "$register_service" "$register_host")

            info "Registering with $register_service on $register_host"
            local -r register_target="admin@$register_host.$PEER_DOMAIN"

            # shellcheck disable=SC2029 # store path expands client-side, glob expands server-side
            echo "$token" | ssh "$register_target" "sudo $register_handler/bin/* '$username'" || {
              error "Registration with $register_service failed"
              exit 1
            }

            # Restart the central service to pick up new registration
            info "Restarting $register_service on $register_host"
            # shellcheck disable=SC2029 # service name intentionally expands on client side
            ssh "$register_target" "sudo systemctl restart '$register_service'" || {
              warn "Failed to restart $register_service"
            }
          fi

          info "Secret $secret_name injected successfully"
        }

        function inject_all_secrets() {
          local -r hostname="$1"
          local -r manifest="$2"

          local secret_names
          secret_names=$(echo "$manifest" | jq -r 'keys[]')

          if [ -z "$secret_names" ]; then
            info "No secrets declared for this host"
            return
          fi

          for secret_name in $secret_names; do
            inject_single_secret "$hostname" "$manifest" "$secret_name"
            echo "" >&2
          done
        }

        function main() {
          local hostname=""
          local action=""
          local secret_name=""

          # Parse arguments
          while [ $# -gt 0 ]; do
            case "$1" in
              --host)
                [[ -z "''${2:-}" ]] && { error "--host requires an argument"; usage; }
                hostname="$2"; shift
                ;;
              --secret)
                [[ -z "''${2:-}" ]] && { error "--secret requires an argument"; usage; }
                action="single"; secret_name="$2"; shift
                ;;
              --all) action="all" ;;
              --list) action="list" ;;
              --dry-run) DRY_RUN=true ;;
              --help|-h) usage ;;
              *)
                error "Unknown option: $1"
                usage
                ;;
            esac
            shift
          done

          [ -z "$hostname" ] && {
            error "--host is required"
            usage
          }
          [ -z "$action" ] && {
            error "One of --secret, --all, or --list is required"
            usage
          }

          validate_hostname "$hostname"

          local -r target="admin@$hostname.$PEER_DOMAIN"
          local -r manifest=$(build_manifest "$hostname")

          case "$action" in
            list)
              list_secrets "$manifest"
              ;;
            all)
              require_ssh_reachable "$target"
              inject_all_secrets "$hostname" "$manifest"
              ;;
            single)
              require_ssh_reachable "$target"
              inject_single_secret "$hostname" "$manifest" "$secret_name"
              ;;
          esac
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

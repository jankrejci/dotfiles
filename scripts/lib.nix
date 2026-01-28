# Shared shell functions for deployment scripts
{pkgs}:
pkgs.writeShellScript "script-lib" ''
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

  # Ensure NETBIRD_API_TOKEN is set from agenix secret, environment, or interactive prompt
  function require_netbird_token() {
    [ -n "''${NETBIRD_API_TOKEN:-}" ] && return

    local -r master_key="$HOME/.age/master.txt"
    local -r secret_file="secrets/netbird-api-token.age"

    # Try to decrypt from agenix secret
    if [ -f "$master_key" ] && [ -f "$secret_file" ]; then
      local age_output
      age_output=$(age -d -i "$master_key" "$secret_file" 2>&1) || {
        error "Failed to decrypt Netbird API token from $secret_file"
        error "$age_output"
        exit 1
      }
      NETBIRD_API_TOKEN="$age_output"
      export NETBIRD_API_TOKEN
      info "Netbird API token loaded from agenix secret"
      return
    fi

    # Fallback to interactive prompt if secret file doesn't exist
    warn "NETBIRD_API_TOKEN not set and secret file not found"
    NETBIRD_API_TOKEN=$(ask_for_token "Netbird API token")
    export NETBIRD_API_TOKEN
  }

  # Load WiFi credentials from agenix secret
  # Usage: load_wifi_credentials <ssid>
  # Expects secrets/wifi-credentials.age to contain JSON: {"SSID": "password", ...}
  function load_wifi_credentials() {
    local -r ssid="$1"

    [ -n "$ssid" ] || {
      error "load_wifi_credentials: SSID required"
      exit 1
    }

    local -r master_key="$HOME/.age/master.txt"
    local -r secret_file="secrets/wifi-credentials.age"

    [ -f "$master_key" ] || {
      error "Master key not found at $master_key"
      exit 1
    }

    [ -f "$secret_file" ] || {
      error "WiFi credentials file not found at $secret_file"
      exit 1
    }

    local credentials
    local age_output
    age_output=$(age -d -i "$master_key" "$secret_file" 2>&1) || {
      error "Failed to decrypt WiFi credentials from $secret_file"
      error "$age_output"
      exit 1
    }
    credentials="$age_output"

    local password
    password=$(echo "$credentials" | jq -r --arg ssid "$ssid" '.[$ssid] // empty') || {
      error "Failed to parse WiFi credentials JSON"
      exit 1
    }

    [ -n "$password" ] || {
      error "No credentials found for SSID '$ssid'"
      info "Available SSIDs:"
      echo "$credentials" | jq -r 'keys[]' | sed 's/^/  - /' >&2
      exit 1
    }

    WIFI_SSID="$ssid"
    WIFI_PASSWORD="$password"
    export WIFI_SSID WIFI_PASSWORD
    info "WiFi credentials loaded for $ssid"
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
''

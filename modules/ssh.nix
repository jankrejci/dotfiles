{
  config,
  pkgs,
  ...
}: let
  gitRepo = "https://raw.githubusercontent.com/jankrejci/dotfiles";
  gitBranch = "main";
  keysFile = "ssh-authorized-keys.conf";
  keysFolder = "/var/cache/ssh";
  keysPath = "${keysFolder}/${keysFile}";
  keysUser = "nobody";
  keysGroup = "nogroup";
in {
  # Use the folder for the key cache, keys are valid at least 1 minute
  systemd.tmpfiles.settings = {
    "10-ssh-authorized-keys-cache" = {
      "${keysFolder}" = {
        d = {
          mode = "0700";
          user = keysUser;
          group = keysGroup;
          age = "1m";
        };
      };
    };
  };

  # Invoke the cleanup every 5 minutes to get rid of outdated ssh keys
  systemd.timers."systemd-tmpfiles-clean".timerConfig = {
    # Time to wait after boot before first run
    OnBootSec = "5min";
    # Time between subsequent runs
    OnUnitActiveSec = "5min";
  };

  # SSH key fetch script - must be owned by root and not writable by others
  # CRITICAL: Must NEVER fail - any error crashes sshd
  environment.etc."fetch-authorized-keys" = {
    source = pkgs.lib.getExe (pkgs.writeShellApplication {
      name = "fetch-authorized-keys";
      runtimeInputs = with pkgs; [coreutils curl gnugrep gnused];
      text = ''
        readonly USERNAME="$1"
        readonly HOSTNAME="${config.homelab.host.hostName}"
        readonly CACHE_FILE="${keysPath}"
        readonly KEYS_URL="${gitRepo}/refs/heads/${gitBranch}/${keysFile}"

        # Fetch keys from GitHub if cache is missing or empty
        fetch_keys_if_needed() {
          [ -s "$CACHE_FILE" ] && return 0

          local temp_file
          temp_file=$(mktemp)

          # Fetch to temp file for atomic cache update
          # Curl flags:
          #   -f: fail on HTTP errors (404, 500, etc) with non-zero exit code
          #   -s: silent mode (no progress bar or extra output)
          #   -S: show errors even in silent mode (combined -sS)
          #   -H: custom header to bypass GitHub's cache
          #   2>/dev/null: suppress any stderr (defense in depth for sshd)
          curl -f -sS -H "Cache-Control: no-cache" "$KEYS_URL" >"$temp_file" 2>/dev/null || {
            rm -f "$temp_file"
            return 1
          }

          # Verify downloaded file is not empty
          if [ ! -s "$temp_file" ]; then
            rm -f "$temp_file"
            return 1
          fi

          # Atomically replace cache (mv is atomic on same filesystem)
          mv "$temp_file" "$CACHE_FILE"
          return 0
        }

        # Parse CSV and extract keys for specific hostname/username
        extract_keys() {
          local cache_file="$1"
          local hostname="$2"
          local username="$3"

          # Filter out comments and empty lines
          local filtered
          filtered=$(grep -v "^#" "$cache_file" 2>/dev/null)
          [ -z "$filtered" ] && return 0

          # Match lines for this hostname
          local matched
          matched=$(echo "$filtered" | grep "^''${hostname}[[:space:]]*," 2>/dev/null)
          [ -z "$matched" ] && return 0

          # Parse CSV and extract keys for matching username
          echo "$matched" | while IFS=, read -r _ user key; do
            # Trim whitespace from user and key fields
            user=$(echo "$user" | tr -d ' \t')
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            # Output key if username matches
            if [ "$user" = "$username" ]; then
              echo "$key"
            fi
          done
          # Ensure loop always exits 0 even if last iteration didn't match
          return 0
        }

        # Main execution
        main() {
          fetch_keys_if_needed || exit 0

          if [ -s "$CACHE_FILE" ]; then
            extract_keys "$CACHE_FILE" "$HOSTNAME" "$USERNAME"
          fi

          exit 0
        }

        main
      '';
    });
    mode = "0555";
    user = "root";
    group = "root";
  };

  # Configure SSH to use the AuthorizedKeysCommand
  services.openssh = {
    enable = true;

    # During Netbird migration: listen on all interfaces
    # Security enforced via firewall (only wg0 and nb-homelab allowed)
    # After migration: can remove this comment and keep config
    listenAddresses = [];

    # Don't open firewall globally - use interface-specific rules below
    openFirewall = false;

    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      AuthorizedKeysCommand = "/etc/fetch-authorized-keys %u";
      AuthorizedKeysCommandUser = keysUser;
    };
  };

  # Restrict SSH access to VPN interface only
  networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [22];

  systemd.services.sshd.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };

  # Basic fail2ban for defense against internal threats
  services.fail2ban.enable = true;
}

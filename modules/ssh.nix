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

  # Load keys from the github repository
  # Format: hostname, user, key (spaces after commas allowed, one entry per line)
  # Comments start with #
  # AuthorizedKeysCommand receives username as $1
  # There is very limited env, use full paths
  fetchAuthorizedKeys = ''
    #!${pkgs.stdenv.shell}

    USERNAME="$1"
    HOSTNAME="${config.hosts.self.hostName}"

    # Check if there are cached ssh keys, if not fetch it from github
    if [ ! -f "${keysPath}" ]; then
      "${pkgs.curl}/bin/curl" -H "Cache-Control: no-cache" "${gitRepo}/refs/heads/${gitBranch}/${keysFile}" > "${keysPath}"
    fi

    # Parse CSV format and filter by hostname and username
    # Format: hostname, user, key (spaces after commas are trimmed)
    "${pkgs.gnugrep}/bin/grep" -v "^#" "${keysPath}" | "${pkgs.gnugrep}/bin/grep" "^$HOSTNAME[[:space:]]*," | while IFS=, read -r host user key; do
      # Trim leading/trailing whitespace from user and key
      user=$(echo "$user" | "${pkgs.coreutils}/bin/tr" -d ' \t')
      key=$(echo "$key" | "${pkgs.gnused}/bin/sed" 's/^[[:space:]]*//;s/[[:space:]]*$//')

      if [ "$user" = "$USERNAME" ]; then
        echo "$key"
      fi
    done
  '';
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

  # The sshds AuthorizedKeysCommand must be owned by root and not writable by others
  environment.  etc."fetch-authorized-keys" = {
    source = pkgs.writeScript "fetch-authorized-keys" fetchAuthorizedKeys;
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

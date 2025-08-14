{
  config,
  pkgs,
  ...
}: let
  gitRepo = "https://raw.githubusercontent.com/jankrejci/dotfiles";
  gitBranch = "main";
  keysFile = "ssh-authorized-keys.pub";
  keysFolder = "/var/cache/ssh";
  keysPath = "${keysFolder}/${keysFile}";
  keysUser = "nobody";
  keysGroup = "nogroup";

  # Load keys from the github repository
  # There is very limited env, use full paths
  fetchAuthorizedKeys = ''
    #!${pkgs.stdenv.shell}

    # Check if there are cached ssh keys, if not fetch it from github
    if [ ! -f "${keysPath}" ]; then
      "${pkgs.curl}/bin/curl" -H "Cache-Control: no-cache" "${gitRepo}/refs/heads/${gitBranch}/hosts/${config.hosts.self.hostName}/${keysFile}" > "${keysPath}"
    fi

    "${pkgs.coreutils}/bin/cat" "${keysPath}"
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

    listenAddresses = [
      {
        addr = config.hosts.self.ipAddress;
        port = 22;
      }
    ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      AuthorizedKeysCommand = "/etc/fetch-authorized-keys";
      AuthorizedKeysCommandUser = keysUser;
    };
  };

  systemd.services.sshd.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };
}

{ pkgs, lib, hostConfig, ... }:
let
  gitRepo = "https://raw.githubusercontent.com/jankrejci/dotfiles";
  gitBranch = "jkr/install";
  keysFile = "ssh-authorized-keys.pub";

  fetchAuthorizedKeys = ''
    #!${pkgs.stdenv.shell}

    "${pkgs.curl}/bin/curl" "${gitRepo}/refs/heads/${gitBranch}/hosts/${hostConfig.hostName}/${keysFile}"
  '';
in
{
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
      { addr = hostConfig.ipAddress; port = 22; }
    ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = lib.mkForce "no";
      AuthorizedKeysCommand = "/etc/fetch-authorized-keys";
      AuthorizedKeysCommandUser = "nobody";
    };
  };

  systemd.services.sshd.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };
}

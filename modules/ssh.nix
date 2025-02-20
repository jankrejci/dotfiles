{ pkgs, lib, hostConfig, ... }:
let
  # Define the script to fetch authorized keys
  fetchAuthorizedKeys = ''
    #!/bin/bash
    USER=$1
    DOTFILES_DIR="/home/$USER/dotfiles"
    GIT_REPO="https://github.com/jankrejci/dotfiles"

    # Ensure the key directory exists
    mkdir -p "$DOTFILES_DIR"

    # Pull the latest keys (or clone if not present)
    if [ -d "$DOTFILES_DIR/.git" ]; then
        git -C "$DOTFILES_DIR" pull
    else
        git clone "$GIT_REPO" "$DOTFILES_DIR"
    fi

    # Output the relevant keys
    cat "$DOTFILES_DIR/hosts/${hostConfig.hostName}/ssh-authorized-keys.pub"
  '';
in
{
  # Make sure Git is installed
  environment.systemPackages = [ pkgs.git ];

  # Deploy the fetch-authorized-keys script
  environment.etc."fetch-authorized-keys".source = pkgs.writeScript "fetch-authorized-keys" fetchAuthorizedKeys;

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

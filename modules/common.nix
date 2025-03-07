{ config, lib, pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  time.timeZone = "Europe/Prague";
  console.keyMap = "us";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "cs_CZ.UTF-8";
      LC_IDENTIFICATION = "cs_CZ.UTF-8";
      LC_MEASUREMENT = "cs_CZ.UTF-8";
      LC_MONETARY = "cs_CZ.UTF-8";
      LC_NAME = "cs_CZ.UTF-8";
      LC_NUMERIC = "cs_CZ.UTF-8";
      LC_PAPER = "cs_CZ.UTF-8";
      LC_TELEPHONE = "cs_CZ.UTF-8";
      LC_TIME = "cs_CZ.UTF-8";
    };
  };

  # Common system packages
  environment.systemPackages = with pkgs; [
    curl
    bash
    unzip
    wget
    coreutils
    rsync
    jq
    vim
    usbutils
    pciutils
    lshw
    bat # cat clone with wings
    eza # ls replacement
    fd # find relplacement
    fzf # cli fuzzy finder
    zoxide # smarter cd command
    ripgrep # search tool 
    nmap # network mapper
    htop # interactive process viewer 
    wireguard-tools
    dig # DNS lookup utility
    sops
    tcpdump
    nix-tree
  ];

  sops = {
    defaultSopsFile = ../hosts/${config.hosts.self.hostName}/secrets.yaml;
    validateSopsFiles = true;

    age = {
      keyFile = "/var/cache/sops/age/keys.txt";
      generateKey = false;
    };
    # Define wireguard relevant secrets
    secrets = {
      "wg_private_key" = {
        mode = "0400";
        owner = "systemd-network";
        restartUnits = [ "systemd-networkd.service" ];
      };
      "endpoint" = {
        mode = "0400";
        owner = "systemd-network";
        restartUnits = [ "systemd-networkd.service" ];
      };
    };
  };

  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;
    listenAddress = config.hosts.self.ipAddress;
  };

  systemd.services.prometheus-node-exporter.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };

  system.stateVersion = "24.11"; # Did you read the comment?
}

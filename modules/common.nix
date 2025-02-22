{ pkgs, hostConfig, ... }:
let
  nameServers = [ "1.1.1.1" "8.8.8.8" ];
in
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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

  # Do not wait to long for interfaces to become online,
  # this is especially handy for notebooks on wifi,
  # where the eth interface is disconnected
  boot.initrd.systemd.network.wait-online.enable = false;
  systemd.network.wait-online = {
    anyInterface = true;
    timeout = 10;
  };

  networking = {
    hostName = hostConfig.hostName;
    firewall.enable = true;
    nameservers = nameServers;
  };

  services.resolved = {
    enable = true;
    dnssec = "true";
    # Explicitely disabled as it interfere with dnsmasq resolving somehow
    dnsovertls = "false";
  };

  sops = {
    defaultSopsFile = ../hosts/${hostConfig.hostName}/secrets.yaml;
    validateSopsFiles = true;

    age = {
      keyFile = "/var/cache/sops/age/keys.txt";
      generateKey = false;
    };
  };

  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;
    listenAddress = hostConfig.ipAddress;
  };

  systemd.services.prometheus-node-exporter.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };

  system.stateVersion = "24.11"; # Did you read the comment?
}

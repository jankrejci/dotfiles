{ pkgs, hostConfig, ... }:
let
  nameServers = [ "1.1.1.1" "8.8.8.8" ];
in
{
  networking.hostName = hostConfig.hostName;
  networking.firewall.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = "Europe/Prague";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
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

  console.keyMap = "us";

  # Common system packages
  environment.systemPackages = with pkgs; [
    unstable.zellij
    unstable.helix
    unstable.nushell
    unstable.broot
    starship
    curl
    bash
    home-manager
    unzip
    wget
    coreutils
    rclone
    rsync
    jq
    vim
    neofetch
    git
    usbutils
    pciutils
    lshw
    brightnessctl
    bat # cat clone with wings
    eza # ls replacement
    fd # find relplacement
    fzf # cli fuzzy finder
    zoxide # smarter cd command
    ripgrep # search tool 
    tealdeer # tldr help tool
    nmap # network mapper
    htop # interactive process viewer 
    wireguard-tools
    dig # DNS lookup utility
    hexyl # hex viewer
    age
    sops
    ssh-to-age
    tcpdump
    nix-tree
  ];

  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "DejaVuSansMono" ]; })
  ];

  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;
    listenAddress = hostConfig.ipAddress;
  };

  systemd.services.prometheus-node-exporter.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };

  # Do not wait to long for interfaces to become online,
  # this is especially handy for notebooks on wifi,
  # where the eth interface is disconnected
  boot.initrd.systemd.network.wait-online.enable = false;
  systemd.network.wait-online = {
    anyInterface = true;
    timeout = 10;
  };

  networking.nameservers = nameServers;
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
      keyFile = "/var/lib/sops/age/keys.txt";
      generateKey = false;
    };

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

  system.stateVersion = "24.11"; # Did you read the comment?
}
